defmodule Hologram.Job.RunnerContentionTest do
  # Two workers reaching for the same queued job at the same moment. What makes exactly one of them
  # run it is the claim's locked read: the loser waits on the winner's transaction, then reads the
  # row as it was committed - running - and leaves it alone.
  #
  # Neither half of that can be seen under the sandboxed case, where every test is one
  # never-committed transaction on one connection, so this lives in the scratch tier with a
  # database of its own and a real session per worker.
  #
  # Both workers have to be IN FLIGHT for the race to be a race: a second worker arriving after the
  # first has committed answers :taken without ever waiting, and would pass just as happily against
  # a claim that took no lock at all. They are held at the row by a third session whose open
  # transaction holds it, and released together.
  #
  # async: false - the tier's modules run one at a time, since each opens raw sessions beside its
  # scratch connection.
  use Hologram.Test.ScratchDatabaseCase, async: false

  import Hologram.Job.Runner

  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.EntityOperations
  alias Hologram.DB.Mapper
  alias Hologram.DB.SchemaReconciler
  alias Hologram.Job
  alias Hologram.Job.RunLock
  alias Hologram.Test.Fixtures.Job.Module1

  defp on_own_session(scratch_opts, fun) do
    {:ok, session} = Postgrex.start_link(scratch_opts)

    route(session, fun)
  end

  # Holds the job's row against every reader until the test lets go, so that both workers are
  # waiting for it rather than arriving one after the other.
  defp start_row_holder(scratch_opts, id, test_pid) do
    statement =
      ~s|SELECT 1 FROM "hologram_data"."#{Mapper.table_name(Module1)}" WHERE "id" = $1 FOR UPDATE|

    Task.async(fn ->
      {:ok, session} = Postgrex.start_link(scratch_opts)

      Postgrex.transaction(session, fn connection ->
        Postgrex.query!(connection, statement, [Codec.encode(id, :id)])

        send(test_pid, :holding)

        receive do
          :release -> :ok
        end
      end)
    end)
  end

  # Each worker with a lock connection of its own, as on two nodes, on the scratch database: advisory
  # locks are per database.
  defp start_worker(scratch_opts, id) do
    run_lock = start_supervised!(Supervisor.child_spec({RunLock, scratch_opts}, id: make_ref()))

    Task.async(fn -> on_own_session(scratch_opts, fn -> process(Module1, id, run_lock) end) end)
  end

  test "one of two workers reaching for a job at the same moment runs it", %{
    scratch: scratch,
    scratch_opts: scratch_opts
  } do
    # A virgin database claims itself and converges to the whole model, so the job type has a table
    # to be queued in.
    route(scratch, fn -> SchemaReconciler.reconcile(DB.reconciliation_context()) end)

    job = route(scratch, fn -> Job.create!(Module1) end)

    holder = start_row_holder(scratch_opts, job.id, self())
    assert_receive :holding, 5_000

    first = start_worker(scratch_opts, job.id)
    second = start_worker(scratch_opts, job.id)

    wait_for_blocked_sessions(scratch_opts, 2)

    send(holder.pid, :release)
    assert {:ok, :ok} = Task.await(holder)

    assert Enum.sort([Task.await(first), Task.await(second)]) == [:done, :taken]

    assert route(scratch, fn -> EntityOperations.get(Module1, job.id) end).status == :done
  end
end
