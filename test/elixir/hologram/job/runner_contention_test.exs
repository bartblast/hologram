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
        Postgrex.query!(connection, statement, [Codec.encode(id, :uuid)])

        send(test_pid, :holding)

        receive do
          :release -> :ok
        end
      end)
    end)
  end

  defp start_worker(scratch_opts, id) do
    Task.async(fn -> on_own_session(scratch_opts, fn -> process(Module1, id) end) end)
  end

  # A worker parked on the row and a worker that has not got there yet look the same to a task that
  # has not returned, so the wait is asserted where it is visible: Postgres itself.
  #
  # The two do not wait on the SAME thing, which is why this counts locks rather than naming one:
  # the first to arrive waits on the transaction holding the row (`transactionid`), and the one
  # queued behind it waits on the row itself (`tuple`), which is how PostgreSQL keeps several
  # waiters for one row in order.
  #
  # Scoped to this database and excluding the observer, because pg_stat_activity is the whole
  # server: the rest of the suite runs against another database at the same moment.
  defp wait_for_blocked_workers(scratch_opts, count) do
    {:ok, observer} = Postgrex.start_link(scratch_opts)

    statement = """
    SELECT count(*) FROM pg_catalog.pg_stat_activity
    WHERE "datname" = current_database() AND "wait_event_type" = 'Lock'
      AND "pid" <> pg_backend_pid()
    """

    wait_until(fn ->
      %Postgrex.Result{rows: [[blocked]]} = Postgrex.query!(observer, statement, [])

      blocked == count
    end)
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

    wait_for_blocked_workers(scratch_opts, 2)

    send(holder.pid, :release)
    assert {:ok, :ok} = Task.await(holder)

    assert Enum.sort([Task.await(first), Task.await(second)]) == [:done, :taken]

    assert route(scratch, fn -> EntityOperations.get(Module1, job.id) end).status == :done
  end
end
