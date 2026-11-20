defmodule Hologram.DB.SchemaReconcilerContentionTest do
  # Two VMs reconciling one database at the same moment - a dev server beside an iex -S mix
  # session, or two mix test runs, say. The advisory lock reconcile/1 takes first makes them take
  # turns, and the second reads the marker only once it holds the lock, so it finds the first one's
  # upgrade done. That needs commits other sessions see, which the sandboxed suite can't give.
  #
  # The test holds that lock itself until both wait on it, so they always race: two that ran one
  # after the other would pass without the lock.
  #
  # async: false - every test of the tier opens raw sessions beside its scratch connection,
  # several in the contention suites, so the tier's modules run one at a time to keep the
  # server's connection count bounded.
  use Hologram.Test.ScratchDatabaseCase, async: false

  alias Hologram.Auth.RoleGrant
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.DB.SchemaReconciler
  alias Hologram.Test.Fixtures.Entity.Module1

  @context %{
    otp_app: "hologram",
    env: "test",
    hologram_version: "0.5.0",
    timestamp: ~U[2026-07-20 12:30:00.000000Z]
  }

  # An upgrade step standing in for a later release's, creating a table that fails if it runs
  # again.
  @probe_step {2, [~s{CREATE TABLE "hologram_system"."upgrade_probe" ("id" integer)}]}

  # The reconciler's advisory lock key, frozen forever (see @advisory_lock_key in
  # Hologram.DB.SchemaReconciler), so repeating it here can't go stale.
  @reconciliation_lock_key 4_787_000_136_577_093_832

  defp probe_exists? do
    statement = ~s{SELECT to_regclass('"hologram_system"."upgrade_probe"') IS NOT NULL}
    {:ok, %{rows: [[exists?]]}} = Connection.query(statement)

    exists?
  end

  # The grant store is dropped so the run converges Module1 alone, as the reconciler's own tests do.
  defp reconcile_context(system_upgrades) do
    mapping =
      [Module1]
      |> Mapper.derive!([])
      |> Map.drop([RoleGrant])

    Map.merge(@context, %{mapping: mapping, system_upgrades: system_upgrades})
  end

  # A reconciliation on a session of its own, like another VM's.
  defp start_reconciler(context, scratch_opts) do
    Task.async(fn ->
      {:ok, session} = Postgrex.start_link(scratch_opts)

      route(session, fn -> SchemaReconciler.reconcile(context).status end)
    end)
  end

  describe "reconcile/1" do
    test "upgrades once across two reconciliations racing for it", %{
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      # Claimed at layout 1, whatever steps the running Hologram has.
      claim_context = reconcile_context([])
      route(scratch, fn -> SchemaReconciler.reconcile(claim_context) end)

      {:ok, holder} = Postgrex.start_link(scratch_opts)
      Postgrex.query!(holder, "SELECT pg_advisory_lock($1)", [@reconciliation_lock_key])

      context = reconcile_context([@probe_step])

      reconcilers = Enum.map(1..2, fn _index -> start_reconciler(context, scratch_opts) end)

      wait_for_blocked_sessions(scratch_opts, 2)
      Postgrex.query!(holder, "SELECT pg_advisory_unlock($1)", [@reconciliation_lock_key])

      # The second through the lock finds the step done, rather than failing on a table that
      # already exists.
      assert Task.await_many(reconcilers, 30_000) == [:managed, :managed]

      route(scratch, fn ->
        assert probe_exists?()
        assert SchemaReconciler.read_marker().system_schema_version == 2
      end)
    end
  end
end
