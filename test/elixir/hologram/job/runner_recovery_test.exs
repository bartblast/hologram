defmodule Hologram.Job.RunnerRecoveryTest do
  # A run cut short ends failed: a pass fails each running job whose run lock no session holds, and
  # leaves the ones whose worker still holds it.
  #
  # The worker and the pass have to be separate sessions with committed rows between them, as on
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

  # A virgin database claims itself and converges to the whole model, so the job type has a table
  # to be queued in.
  setup %{scratch: scratch, scratch_opts: scratch_opts} do
    route(scratch, fn -> SchemaReconciler.reconcile(DB.reconciliation_context()) end)

    [
      job: route(scratch, fn -> Job.create!(Module1) end),
      sweeper_lock: start_run_lock(scratch_opts),
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

  defp sweep(scratch, run_lock) do
    route(scratch, fn -> pass([Module1], run_lock) end)
  end

  test "leaves a running job whose worker holds its lock, and fails it once the worker is gone",
       context do
    %{job: job, scratch: scratch, sweeper_lock: sweeper_lock, worker_lock: worker_lock} = context

    assert {:claimed, _job} = route(scratch, fn -> claim(Module1, job.id, worker_lock) end)

    assert sweep(scratch, sweeper_lock) == 0
    assert status(scratch, job.id) == :running

    # What a node that stops leaves behind: a session that ended, and the server frees its lock
    # once it notices.
    :ok = :gen_statem.stop(worker_lock)

    wait_until(fn ->
      sweep(scratch, sweeper_lock)

      status(scratch, job.id) == :failed
    end)

    assert route(scratch, fn -> EntityOperations.get(Module1, job.id) end).error =~
             "the run was cut short before its outcome was recorded"
  end

  test "fails a job whose outcome could not be recorded", context do
    %{job: job, scratch: scratch, sweeper_lock: sweeper_lock, worker_lock: worker_lock} = context
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
    assert sweep(scratch, sweeper_lock) == 0
    assert status(scratch, job.id) == :failed
  end

  # A run that records its outcome and gives its lock up after the pass read the row as running:
  # the pass finds the lock free, and only the read under the row lock tells it the run is over.
  test "leaves a job whose outcome is recorded while the pass looks at it", context do
    %{job: job, scratch: scratch, scratch_opts: scratch_opts, sweeper_lock: sweeper_lock} =
      context

    table = ~s|"hologram_data"."#{Mapper.table_name(Module1)}"|
    test_pid = self()

    :ok = route(scratch, fn -> EntityOperations.update(Module1, job.id, %{status: :running}) end)

    # The outcome write of a run, held open until the pass is waiting on its row.
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

        route(session, fn -> pass([Module1], sweeper_lock) end)
      end)

    wait_for_blocked_sessions(scratch_opts, 1)

    send(recorder.pid, :commit)
    assert {:ok, :ok} = Task.await(recorder)

    assert Task.await(sweeper) == 0

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
