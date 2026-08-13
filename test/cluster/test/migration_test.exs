defmodule HologramClusterTests.MigrationTest do
  # async: false - every scenario owns the whole migrations database, planting schema
  # state that a concurrent scenario would see.
  use HologramClusterTests.TestCase, async: false

  import HologramClusterTests.MigrationHelpers

  alias Hologram.Migrator

  setup do
    reset_migrations_database!()

    :ok
  end

  defp peer_database(peer) do
    {:ok, %{rows: [[database]]}} =
      rpc(peer, Hologram.DB.Connection, :query, ["SELECT current_database()", []])

    database
  end

  describe "release step, then boot" do
    test "the boot-time apply finds nothing pending" do
      # The deploy pipeline's step, before any node rolls: same entry the boot uses,
      # so what it applies is what the booting nodes would have applied themselves.
      with_migrations_db(fn -> Migrator.run(migrations(), model(), prod_context()) end)

      applied_by_release_step = applied_version_rows()

      peer_1 = start_migration_peer(1)
      peer_2 = start_migration_peer(2)

      assert serving?(peer_1)
      assert serving?(peer_2)

      # Both nodes really are production instances pointed at this database - without
      # this the assertions below would hold just as well for nodes that never had a
      # migration mechanism to run.
      assert rpc(peer_1, Hologram, :env, []) == :prod
      assert rpc(peer_2, Hologram, :env, []) == :prod
      assert peer_database(peer_1) == migrations_database()

      # Identical rows, timestamps included: the nodes found the chain applied and
      # recorded nothing of their own.
      assert applied_version_rows() == applied_by_release_step
      assert length(applied_by_release_step) == 4
    end
  end
end
