defmodule HologramClusterTests.MigrationTest do
  # async: false - every scenario owns the whole migrations database, planting schema
  # state that a concurrent scenario would see.
  use HologramClusterTests.TestCase, async: false

  import HologramClusterTests.MigrationHelpers

  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.Migrator

  setup do
    reset_migrations_database!()

    :ok
  end

  defp data_columns(table) do
    statement = """
    SELECT "column_name"
    FROM "information_schema"."columns"
    WHERE "table_schema" = 'hologram_data' AND "table_name" = $1
    """

    with_migrations_db(fn ->
      {:ok, %{rows: rows}} = Connection.query(statement, [table])

      Enum.map(rows, fn [name] -> name end)
    end)
  end

  defp peer_database(peer) do
    {:ok, %{rows: [[database]]}} =
      rpc(peer, Hologram.DB.Connection, :query, ["SELECT current_database()", []])

    database
  end

  describe "concurrent boot" do
    test "the chain applies exactly once across nodes booting at the same moment" do
      # Started sequentially and left idle: :peer.start_link ties a peer's lifetime to
      # the process that started it, so starting them inside the tasks below would kill
      # them with the tasks. Only the app boot - a plain rpc - goes concurrent, and that
      # is the part the advisory lock arbitrates.
      peers = Enum.map(1..3, &start_migration_peer(&1, boot_app: false))

      results =
        peers
        |> Enum.map(fn peer -> Task.async(fn -> boot_app(peer) end) end)
        |> Task.await_many(60_000)

      assert Enum.all?(results, &match?({:ok, _apps}, &1))
      assert Enum.all?(peers, &serving?/1)

      # One row per version and nothing repeated: the node that took the lock applied
      # the chain, and the others re-read the bookkeeping inside their own transaction
      # and found the work already done.
      versions = Enum.map(applied_version_rows(), fn {version, _applied_at} -> version end)

      assert versions == Enum.map(migrations(), & &1.version)

      mapping = Mapper.derive_from_model!(model())

      assert with_migrations_db(fn -> Migrator.check_drift!(mapping) end) == :ok
    end
  end

  describe "kill and resume" do
    test "the next boot applies only what the interrupted deploy had not" do
      # A node killed after file one commits and a database with only file one applied
      # are the same state - per-file transactions leave nothing in between - so the
      # interrupted deploy is planted rather than raced.
      plant_applied_prefix!(1)

      [planted_row] = applied_version_rows()

      peer = start_migration_peer(1)

      assert serving?(peer)

      rows = applied_version_rows()

      assert Enum.map(rows, fn {version, _applied_at} -> version end) ==
               Enum.map(migrations(), & &1.version)

      # Untouched timestamp: the resumed node started at the first pending file rather
      # than replaying one already recorded.
      assert hd(rows) == planted_row

      columns = data_columns("entities_item")

      assert "slug" in columns
      assert "parent_id" in columns
    end
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
