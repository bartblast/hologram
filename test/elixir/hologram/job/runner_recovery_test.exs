defmodule Hologram.Job.RunnerRecoveryTest do
  # A run cut short counts as a failed attempt: a sweep puts each running job whose run lock no
  # session holds back to wait, or leaves it failed on its last attempt, and leaves the ones whose
  # worker still holds it.
  #
  # The worker and the sweep have to be separate sessions with committed rows between them, as on
  # two nodes - under the sandboxed case every test is one never-committed transaction on one
  # connection - so this lives in the scratch tier with a database of its own.
  #
  # async: false - the tier's modules run one at a time, since each opens raw sessions beside its
  # scratch connection.
  use Hologram.Test.ScratchDatabaseCase, async: false

  import ExUnit.CaptureLog
  import Hologram.Job.Runner

  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.EntityOperations
  alias Hologram.DB.Mapper
  alias Hologram.DB.SchemaReconciler
  alias Hologram.Job
  alias Hologram.Job.RunLock
  alias Hologram.Test.Fixtures.Job.Module1
  alias Hologram.Test.Fixtures.Job.Module3

  # A virgin database claims itself and converges to the whole model, so the job type has a table
  # to be queued in.
  setup %{scratch: scratch, scratch_opts: scratch_opts} do
    route(scratch, fn -> SchemaReconciler.reconcile(DB.reconciliation_context()) end)

    [
      job: route(scratch, fn -> Job.create!(Module1) end),
      worker_lock: start_run_lock(scratch_opts)
    ]
  end

  # On the scratch database: advisory locks are per database.
  defp start_run_lock(scratch_opts) do
    start_supervised!(Supervisor.child_spec({RunLock, scratch_opts}, id: make_ref()))
  end

  defp status(scratch, id) do
    route(scratch, fn -> EntityOperations.get(Module1, id).status end)
  end

  defp sweep_over(scratch) do
    route(scratch, fn -> sweep([Module1], MapSet.new()) end)
  end

  test "leaves a running job whose worker holds its lock, and fails it once the worker is gone",
       context do
    %{job: job, scratch: scratch, worker_lock: worker_lock} = context

    assert {:claimed, _job} = route(scratch, fn -> claim(Module1, job.id, worker_lock) end)

    assert sweep_over(scratch) == :ok
    assert status(scratch, job.id) == :running

    # What a node that stops leaves behind: a session that ended, and the server frees its lock
    # once it notices.
    :ok = :gen_statem.stop(worker_lock)

    wait_until(fn ->
      sweep_over(scratch)

      status(scratch, job.id) == :failed
    end)

    assert route(scratch, fn -> EntityOperations.get(Module1, job.id) end).error =~
             "the run was cut short before its outcome was recorded"
  end

  test "puts a job with attempts left back to wait once its worker is gone", context do
    %{scratch: scratch, worker_lock: worker_lock} = context

    job = route(scratch, fn -> Job.create!(Module3, [outcome: :ok], trust: true) end)
    read = fn -> route(scratch, fn -> EntityOperations.get(Module3, job.id) end) end

    assert {:claimed, _job} = route(scratch, fn -> claim(Module3, job.id, worker_lock) end)

    :ok = :gen_statem.stop(worker_lock)

    wait_until(fn ->
      route(scratch, fn -> sweep([Module3], MapSet.new()) end)

      read.().status == :queued
    end)

    row = read.()

    assert row.attempt == 1
    assert row.error =~ "the run was cut short before its outcome was recorded"
    assert DateTime.compare(row.scheduled_at, DateTime.utc_now()) == :gt
  end

  # The way the worker ends a run past its limit: killed mid-run, its lock given up for it, and the
  # attempt recorded.
  test "records a run killed for passing its time limit", context do
    %{scratch: scratch, worker_lock: worker_lock} = context

    job = route(scratch, fn -> Job.create!(Module3, [outcome: :hang], trust: true) end)
    read = fn -> route(scratch, fn -> EntityOperations.get(Module3, job.id) end) end

    run = spawn(fn -> route(scratch, fn -> process(Module3, job.id, worker_lock) end) end)

    wait_until(fn -> read.().status == :running end)

    monitor_ref = Process.monitor(run)
    Process.exit(run, :kill)
    assert_receive {:DOWN, ^monitor_ref, :process, ^run, :killed}, 5_000

    RunLock.release(worker_lock, lock_name(Module3, job.id))

    assert route(scratch, fn -> time_out(Module3, job.id, 5_000) end) == :ok

    row = read.()

    assert row.status == :queued
    assert row.attempt == 1
    assert row.error =~ "the run passed its time limit of 5000 ms and was killed"
  end

  test "fails a job whose outcome could not be recorded", context do
    %{job: job, scratch: scratch, worker_lock: worker_lock} = context
    table = ~s|"hologram_data"."#{Mapper.table_name(Module1)}"|

    # Refuses every write but the claim's, so the outcome write fails.
    Postgrex.query!(
      scratch,
      "CREATE FUNCTION public.refuse_outcome() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.status <> 'running' THEN RAISE EXCEPTION 'outcome refused'; END IF; RETURN NEW; END $$",
      []
    )

    Postgrex.query!(
      scratch,
      "CREATE TRIGGER refuse_outcome BEFORE UPDATE ON #{table} FOR EACH ROW EXECUTE FUNCTION public.refuse_outcome()",
      []
    )

    process = fn -> route(scratch, fn -> process(Module1, job.id, worker_lock) end) end
    capture_log(fn -> assert_raise Postgrex.Error, ~r/outcome refused/, process end)

    assert status(scratch, job.id) == :running

    Postgrex.query!(scratch, "DROP TRIGGER refuse_outcome ON #{table}", [])

    # The worker's lock connection is still up: what frees the job is the release after the failed
    # outcome write.
    assert sweep_over(scratch) == :ok
    assert status(scratch, job.id) == :failed
  end

  # A run that records its outcome and gives its lock up after the sweep read the row as running:
  # the sweep finds the lock free, and only the read under the row lock tells it the run is over.
  test "leaves a job whose outcome is recorded while the sweep looks at it", context do
    %{job: job, scratch: scratch, scratch_opts: scratch_opts} = context

    table = ~s|"hologram_data"."#{Mapper.table_name(Module1)}"|
    test_pid = self()

    :ok =
      route(scratch, fn ->
        EntityOperations.update(Module1, job.id, %{attempt: 1, status: :running})
      end)

    # The outcome write of a run, held open until the sweep is waiting on its row.
    recorder =
      Task.async(fn ->
        {:ok, session} = Postgrex.start_link(scratch_opts)

        Postgrex.transaction(session, fn connection ->
          Postgrex.query!(connection, ~s|UPDATE #{table} SET "status" = 'done' WHERE "id" = $1|, [
            Codec.encode(job.id, :uuid)
          ])

          send(test_pid, :recording)

          receive do
            :commit -> :ok
          end
        end)
      end)

    assert_receive :recording, 5_000

    sweeper =
      Task.async(fn ->
        {:ok, session} = Postgrex.start_link(scratch_opts)

        route(session, fn -> sweep([Module1], MapSet.new()) end)
      end)

    wait_for_blocked_sessions(scratch_opts, 1)

    send(recorder.pid, :commit)
    assert {:ok, :ok} = Task.await(recorder)

    assert Task.await(sweeper) == :ok

    row = route(scratch, fn -> EntityOperations.get(Module1, job.id) end)

    assert row.status == :done
    assert row.error == nil
  end

  # A row being inserted with a reference to the job holds the job's row FOR KEY SHARE until its
  # transaction ends, and a run must not wait on it - past the driver's timeout, the outcome write
  # would fail and a job that finished would be failed as cut short.
  test "runs a job while a row referencing it is being inserted", context do
    %{job: job, scratch: scratch, scratch_opts: scratch_opts, worker_lock: worker_lock} = context
    table = ~s|"hologram_data"."#{Mapper.table_name(Module1)}"|
    test_pid = self()

    # The lock the foreign key check of such an insert takes, held open until the run is over.
    referrer =
      Task.async(fn ->
        {:ok, session} = Postgrex.start_link(scratch_opts)

        Postgrex.transaction(session, fn connection ->
          Postgrex.query!(connection, ~s|SELECT 1 FROM #{table} WHERE "id" = $1 FOR KEY SHARE|, [
            Codec.encode(job.id, :uuid)
          ])

          send(test_pid, :referencing)

          receive do
            :commit -> :ok
          end
        end)
      end)

    assert_receive :referencing, 5_000

    assert route(scratch, fn -> process(Module1, job.id, worker_lock) end) == :done
    assert status(scratch, job.id) == :done

    send(referrer.pid, :commit)
    assert {:ok, :ok} = Task.await(referrer)
  end
end
