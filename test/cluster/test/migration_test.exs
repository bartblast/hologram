defmodule HologramClusterTests.MigrationTest do
  # async: false - every scenario owns the whole migrations database, planting schema
  # state that a concurrent scenario would see.
  use HologramClusterTests.TestCase, async: false

  import HologramClusterTests.MigrationHelpers

  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.DB.SchemaReconciler
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

  # pg_type, not pg_enum: a type with no values has no labels to find, so asking for
  # its labels answers [] whether or not it exists.
  defp enum_type_exists?(name) do
    statement = """
    SELECT 1
    FROM pg_catalog.pg_type t
    JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'hologram_data' AND t.typname = $1 AND t.typtype = 'e'
    """

    with_migrations_db(fn ->
      {:ok, %{rows: rows}} = Connection.query(statement, [name])

      rows != []
    end)
  end

  defp enum_values(type_name) do
    statement = """
    SELECT e.enumlabel
    FROM pg_catalog.pg_enum e
    JOIN pg_catalog.pg_type t ON t.oid = e.enumtypid
    WHERE t.typname = $1
    ORDER BY e.enumsortorder
    """

    with_migrations_db(fn ->
      {:ok, %{rows: rows}} = Connection.query(statement, [type_name])

      Enum.map(rows, fn [value] -> value end)
    end)
  end

  defp index_validity(index) do
    statement = """
    SELECT i."indisvalid"
    FROM pg_catalog.pg_index i
    JOIN pg_catalog.pg_class ic ON ic.oid = i."indexrelid"
    JOIN pg_catalog.pg_class c ON c.oid = i."indrelid"
    JOIN pg_catalog.pg_namespace n ON n.oid = c."relnamespace"
    WHERE n."nspname" = 'hologram_data' AND ic."relname" = $1
    """

    with_migrations_db(fn ->
      case Connection.query(statement, [index]) do
        {:ok, %{rows: [[valid]]}} -> valid
        {:ok, %{rows: []}} -> :absent
      end
    end)
  end

  defp item_count do
    statement = ~s{SELECT COUNT(*) FROM "hologram_data"."entities_item"}

    with_migrations_db(fn ->
      {:ok, %{rows: [[count]]}} = Connection.query(statement)

      count
    end)
  end

  defp invalidate_index(index) do
    statement = """
    UPDATE pg_catalog.pg_index SET "indisvalid" = false
    FROM pg_catalog.pg_class ic
    WHERE ic.oid = pg_index."indexrelid" AND ic."relname" = $1
    """

    with_migrations_db(fn -> {:ok, _result} = Connection.query(statement, [index]) end)
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

  describe "concurrent index build" do
    test "the tail index is built on a populated table and comes out valid" do
      # Through f3: the table stands and carries rows, so f4's index cannot be built
      # inside its transaction and goes to the tail, which builds it concurrently.
      plant_applied_prefix!(3)

      insert_item = """
      INSERT INTO "hologram_data"."entities_item"
        ("id", "slug", "title", "created_at", "updated_at", "$revisions")
      VALUES (gen_random_uuid(), $1, $2, now(), now(), '{}')
      """

      with_migrations_db(fn ->
        {:ok, _result} = Connection.query(insert_item, ["one", "First"])
        {:ok, _result} = Connection.query(insert_item, ["two", "Second"])
        {:ok, _result} = Connection.query(insert_item, ["three", "Third"])
      end)

      peer = start_migration_peer(1)

      assert serving?(peer)
      assert item_count() == 3

      # Valid, not merely present: a concurrent build that fails partway leaves the
      # index in the catalog serving no query while every write maintains it.
      assert index_validity("entities_item_parent_id_$idx") == true

      assert Enum.map(applied_version_rows(), fn {version, _applied_at} -> version end) ==
               Enum.map(migrations(), & &1.version)
    end

    test "a build interrupted partway is rebuilt by the next boot" do
      first_peer = start_migration_peer(1)

      assert serving?(first_peer)

      index = "entities_item_parent_id_$idx"

      # What a node killed during its concurrent build leaves behind: the file is
      # recorded applied - it committed before the build began - while the index stays
      # in the catalog serving no query and slowing every write.
      invalidate_index(index)

      assert index_validity(index) == false

      next_peer = start_migration_peer(2)

      assert serving?(next_peer)
      assert index_validity(index) == true
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

  describe "mechanism selection" do
    test "a production node applies its chain at boot" do
      peer = start_migration_peer(1)

      assert serving?(peer)

      # The migration mechanism ran because the node's environment selected it - the
      # dev and test halves of that choice are pinned where they are reachable, in the
      # framework's own child-spec test, since a dev node here would need the live
      # reload watcher, which assumes Mix.
      assert rpc(peer, Hologram, :env, []) == :prod

      assert Enum.map(applied_version_rows(), fn {version, _applied_at} -> version end) ==
               Enum.map(migrations(), & &1.version)
    end

    test "a production node boots on a history that designates a user entity before any role" do
      peer = start_migration_peer(1)

      assert serving?(peer)

      # The store's role enum takes its values from the app's roles, and this app declares
      # none - so the model derives a type with NO values and the node boots on one. An
      # introspection query starting from the labels cannot see such a type at all, which
      # made every boot after the first refuse itself on drift it had created.
      assert enum_type_exists?("hologram_role_grant_role_$enum")

      # The premise, asserted rather than assumed: declaring a role anywhere in this app
      # puts a value on the type and fails this line, instead of leaving the test passing
      # with nothing left to prove. Whoever adds the first role moves this case.
      assert enum_values("hologram_role_grant_role_$enum") == []
    end

    test "a production node refuses a database managed by schema reconciliation" do
      # The database dev's mechanism would leave behind: converged from the model and
      # carrying a reconciliation marker, with no migration history at all.
      with_migrations_db(fn -> SchemaReconciler.reconcile(reconciliation_context()) end)

      peer = start_migration_peer(1, boot_app: false)

      assert boot_error_message(peer) ==
               "the configured database is managed by schema reconciliation, which " <>
                 "converges dev databases from the model - migrations never apply to " <>
                 "one - point the config at a database of this environment"

      refute serving?(peer)
    end
  end

  describe "refusals" do
    test "drift refuses the booting node while the running one keeps serving" do
      running_peer = start_migration_peer(1)

      assert serving?(running_peer)

      drop_title = ~s(ALTER TABLE "hologram_data"."entities_item" DROP COLUMN "title")
      with_migrations_db(fn -> {:ok, _result} = Connection.query(drop_title) end)

      booting_peer = start_migration_peer(2, boot_app: false)
      message = boot_error_message(booting_peer)

      assert message =~ "schema drift detected"

      assert message =~
               ~s(column "title" on table "entities_item" declared by the model is missing)

      # The refusal is a boot-time gate: the node already serving finished its own boot
      # long before, and nothing revisits that decision underneath it.
      assert serving?(running_peer)
      refute serving?(booting_peer)
    end

    test "a pre-flight refusal names the obstacle, and fixing the data unblocks the deploy" do
      # Through f2 only: the slug column exists and still accepts NULL, which is the
      # state the rows below are legal in and the next file is not.
      plant_applied_prefix!(2)

      insert_item = """
      INSERT INTO "hologram_data"."entities_item"
        ("id", "title", "created_at", "updated_at", "$revisions")
      VALUES (gen_random_uuid(), $1, now(), now(), '{}')
      """

      with_migrations_db(fn ->
        {:ok, _result} = Connection.query(insert_item, ["first"])
        {:ok, _result} = Connection.query(insert_item, ["second"])
      end)

      refused_peer = start_migration_peer(1, boot_app: false)
      message = boot_error_message(refused_peer)

      assert message ==
               ~s(cannot make column "slug" on table "entities_item" required - ) <>
                 "found 2 rows with NULL - declare default: <value>, keep the attribute " <>
                 "optional: true, or fix the data"

      # The way out the message names: give the rows a value, then deploy again.
      fill_slugs = ~s(UPDATE "hologram_data"."entities_item" SET "slug" = "title")
      with_migrations_db(fn -> {:ok, _result} = Connection.query(fill_slugs) end)

      redeployed_peer = start_migration_peer(2)

      assert serving?(redeployed_peer)

      assert Enum.map(applied_version_rows(), fn {version, _applied_at} -> version end) ==
               Enum.map(migrations(), & &1.version)
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
      assert length(applied_by_release_step) == 5
    end
  end
end
