defmodule Hologram.Job.RunnerClaimFailureTest do
  # A claim that fails after taking the job's run lock gives the lock back. Kept, the lock would
  # stack under this session's next claim of the job, and one release after its outcome would
  # leave the job's row looking live for good.
  #
  # The claim is made to fail by a trigger on the job's table, and the failure at commit needs a
  # transaction that really commits - neither fits under the sandboxed case, so this lives in the
  # scratch tier with a database of its own.
  #
  # async: false - the tier's modules run one at a time, since each opens raw sessions beside its
  # scratch connection.
  use Hologram.Test.ScratchDatabaseCase, async: false

  import ExUnit.CaptureLog
  import Hologram.Job.Runner

  alias Hologram.DB
  alias Hologram.DB.EntityOperations
  alias Hologram.DB.Mapper
  alias Hologram.DB.SchemaReconciler
  alias Hologram.Job
  alias Hologram.Job.RunLock
  alias Hologram.Test.Fixtures.Job.Module1

  # A virgin database claims itself and converges to the whole model, so the job type has a table
  # to be queued in, and a trigger on that table refuses the claim's update.
  setup %{scratch: scratch, scratch_opts: scratch_opts} do
    route(scratch, fn -> SchemaReconciler.reconcile(DB.reconciliation_context()) end)

    Postgrex.query!(
      scratch,
      "CREATE FUNCTION public.refuse_claim() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'claim refused'; END $$",
      []
    )

    [
      job: route(scratch, fn -> Job.create!(Module1) end),
      run_lock: start_run_lock(scratch_opts),
      table: ~s|"hologram_data"."#{Mapper.table_name(Module1)}"|
    ]
  end

  # On the scratch database: advisory locks are per database.
  defp start_run_lock(scratch_opts) do
    start_supervised!(Supervisor.child_spec({RunLock, scratch_opts}, id: make_ref()))
  end

  defp assert_claim_given_back(context) do
    %{job: job, run_lock: run_lock, scratch: scratch, scratch_opts: scratch_opts} = context

    claim = fn -> route(scratch, fn -> claim(Module1, job.id, run_lock) end) end

    # A commit the server refuses also ends the connection, which logs it.
    capture_log(fn -> assert_raise Postgrex.Error, ~r/claim refused/, claim end)

    other = start_run_lock(scratch_opts)
    row = route(scratch, fn -> EntityOperations.get(Module1, job.id) end)

    assert RunLock.acquire(other, job.id)
    assert row.status == :queued
  end

  test "gives the run lock back when the claim's update fails", context do
    Postgrex.query!(
      context.scratch,
      "CREATE TRIGGER refuse_claim BEFORE UPDATE ON #{context.table} FOR EACH ROW EXECUTE FUNCTION public.refuse_claim()",
      []
    )

    assert_claim_given_back(context)
  end

  test "gives the run lock back when the claim's commit fails", context do
    Postgrex.query!(
      context.scratch,
      "CREATE CONSTRAINT TRIGGER refuse_claim AFTER UPDATE ON #{context.table} DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.refuse_claim()",
      []
    )

    assert_claim_given_back(context)
  end
end
