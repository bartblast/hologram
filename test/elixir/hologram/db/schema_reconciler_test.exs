defmodule Hologram.DB.SchemaReconcilerTest do
  # async: false - the sandbox isolates data, not locks: DDL on shared relations
  # takes AccessExclusiveLock, which deadlocks with row locks that concurrent
  # sandboxed tests hold until rollback.
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.DB.SchemaReconciler

  alias Hologram.Auth
  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.IndexPlan
  alias Hologram.DB.Introspection
  alias Hologram.DB.Mapper
  alias Hologram.DB.Schema
  alias Hologram.DB.SortKey
  alias Hologram.Reflection
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module19
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module26
  alias Hologram.Test.Fixtures.Entity.Module27
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module4
  alias Hologram.Test.Fixtures.Entity.Module52
  alias Hologram.Test.Fixtures.Role

  @context %{
    otp_app: "hologram",
    env: "test",
    hologram_version: "0.5.0",
    timestamp: ~U[2026-07-20 12:30:00.000000Z]
  }

  @marker %{
    otp_app: "hologram",
    env: "test",
    managed_by: "reconciliation",
    hologram_version: "0.5.0",
    system_schema_version: 1,
    last_reconciled_at: ~U[2026-07-20 12:30:00.000000Z]
  }

  @module2_table ~s("hologram_data"."test_fixtures_entity_module2")

  @reset_hint " - or run mix holo.db.reset to start over, which deletes this database's " <>
                "Hologram data"

  @not_managed_msg "the configured database contains Hologram schemas but no " <>
                     "managed-database marker - it is not managed by schema " <>
                     "reconciliation - drop the \"hologram_system\" and " <>
                     "\"hologram_data\" schemas or point the config at another database"

  # Upgrade steps standing in for a later release's: the first creates a table in hologram_system,
  # which fails if it runs again, and the second changes it, which fails if the first never ran.
  @create_probe_step {2, [~s{CREATE TABLE "hologram_system"."upgrade_probe" ("id" integer)}]}

  @alter_probe_step {3,
                     [~s{ALTER TABLE "hologram_system"."upgrade_probe" ADD COLUMN "note" text}]}

  defp drop_hologram_schemas do
    {:ok, _result} = Connection.query(~s(DROP SCHEMA "hologram_system" CASCADE))
    {:ok, _result} = Connection.query(~s(DROP SCHEMA "hologram_data" CASCADE))
  end

  defp insert_module2_row(b_value, c_value) do
    statement = """
    INSERT INTO "hologram_data"."test_fixtures_entity_module2"
      ("id", "a", "b", "c", "created_at", "server_created_at", "server_created_seq", "server_updated_at", "server_updated_seq", "updated_at", "$revisions")
    VALUES ('00000000-0000-0000-0000-000000000001', TRUE, #{b_value}, #{c_value},
            '2026-01-01 00:00:00+00', '2026-01-01 00:00:00+00', 0, '2026-01-01 00:00:00+00', 0, '2026-01-01 00:00:00+00', '{}')
    """

    {:ok, _result} = Connection.query(statement)
  end

  # The grant store is derived into every mapping - dropped here so a run converges
  # exactly the entity types the test names (its user references would otherwise point
  # at a table outside the mapping). Tests converging the store itself use
  # reconcile_context_with_grant_store/1.
  # The indexes the database holds over Module27's channel reference, by name.
  defp channel_indexes do
    indexes = Introspection.schema().tables["test_fixtures_entity_module27"].indexes

    Map.filter(indexes, fn {_name, index} -> index.columns == ["channel_id"] end)
  end

  defp insert_module2_rows(c_values) do
    c_values
    |> Enum.with_index(1)
    |> Enum.each(fn {c_value, index} ->
      statement = """
      INSERT INTO "hologram_data"."test_fixtures_entity_module2"
        ("id", "a", "b", "c", "created_at", "server_created_at", "server_created_seq", "server_updated_at", "server_updated_seq", "updated_at", "$revisions")
      VALUES ('00000000-0000-0000-0000-00000000000#{index}', TRUE, NULL, '#{c_value}',
              '2026-01-01 00:00:00+00', '2026-01-01 00:00:00+00', 0, '2026-01-01 00:00:00+00', 0, '2026-01-01 00:00:00+00', '{}')
      """

      {:ok, _result} = Connection.query(statement)
    end)
  end

  defp module2_sort_pairs do
    select_statement =
      ~s(SELECT "c", "c_$sort" FROM "hologram_data"."test_fixtures_entity_module2" ) <>
        ~s(ORDER BY "c_$sort")

    {:ok, %{rows: rows}} = Connection.query(select_statement)

    rows
  end

  # Module27's mapping as it would stand if its channel reference were not unique: no unique index,
  # so the index plan gives the reference column its plain one.
  defp non_unique_channel_context do
    [Module26, Module27]
    |> reconcile_context()
    |> update_mapping_indexes(Module27, fn indexes ->
      Map.delete(indexes, "test_fixtures_entity_module27_channel_id_$uidx")
    end)
  end

  # An index standing under another name, as an older naming rule left it - registered under
  # that name too unless the test wants it unknown.
  defp rename_index_by_hand(table, from, to, registered?) do
    {:ok, _result} =
      Connection.query(
        ~s(ALTER INDEX "hologram_data".#{Mapper.quote_identifier(from)} RENAME TO #{Mapper.quote_identifier(to)})
      )

    if registered? do
      statement = """
      UPDATE "hologram_system"."schema_object" SET "name" = $3
      WHERE "kind" = 'index' AND "parent" = $1 AND "name" = $2
      """

      {:ok, _result} = Connection.query(statement, [table, from, to])
    else
      statement = """
      DELETE FROM "hologram_system"."schema_object"
      WHERE "kind" = 'index' AND "parent" = $1 AND "name" = $2
      """

      {:ok, _result} = Connection.query(statement, [table, from])
    end
  end

  @module3_join_table "test_fixtures_entity_module3_a_$join"

  # A join table standing under another name, as an older naming rule left it - registered
  # under that name too unless the test wants it unknown. Its constraints and index keep the
  # names the model derives.
  defp rename_join_table_by_hand(to, registered?) do
    {:ok, _result} =
      Connection.query(
        ~s(ALTER TABLE "hologram_data".#{Mapper.quote_identifier(@module3_join_table)} RENAME TO #{Mapper.quote_identifier(to)})
      )

    if registered? do
      {:ok, _result} =
        Connection.query(
          ~s(UPDATE "hologram_system"."schema_object" SET "name" = $1 WHERE "kind" = 'table' AND "name" = $2),
          [to, @module3_join_table]
        )

      {:ok, _result} =
        Connection.query(
          ~s(UPDATE "hologram_system"."schema_object" SET "parent" = $1 WHERE "parent" = $2),
          [to, @module3_join_table]
        )
    else
      {:ok, _result} =
        Connection.query(
          ~s(DELETE FROM "hologram_system"."schema_object" WHERE "name" = $1 OR "parent" = $1),
          [@module3_join_table]
        )
    end
  end

  # One Module3 row linked to one Module2 row through the join table.
  defp insert_module3_link do
    module1_id = "00000000-0000-0000-0000-0000000000a1"
    module3_id = "00000000-0000-0000-0000-0000000000a3"

    {:ok, _result} =
      Connection.query("""
      INSERT INTO "hologram_data"."test_fixtures_entity_module1"
        ("id", "created_at", "server_created_at", "server_created_seq", "server_updated_at", "server_updated_seq", "updated_at", "$revisions")
      VALUES ('#{module1_id}', now(), now(), 0, now(), 0, now(), '{}')
      """)

    insert_module2_row("NULL", "'x'")

    {:ok, _result} =
      Connection.query("""
      INSERT INTO "hologram_data"."test_fixtures_entity_module3"
        ("id", "c_id", "created_at", "server_created_at", "server_created_seq", "server_updated_at", "server_updated_seq", "updated_at", "$revisions")
      VALUES ('#{module3_id}', '#{module1_id}', now(), now(), 0, now(), 0, now(), '{}')
      """)

    {:ok, _result} =
      Connection.query("""
      INSERT INTO "hologram_data".#{Mapper.quote_identifier(@module3_join_table)}
        ("source_id", "target_id")
      VALUES ('#{module3_id}', '00000000-0000-0000-0000-000000000001')
      """)
  end

  defp insert_module4_row(c_value) do
    insert_statement = """
    INSERT INTO "hologram_data"."test_fixtures_entity_module4"
      ("id", "a", "b", "c", "d", "created_at", "server_created_at", "server_created_seq", "server_updated_at", "server_updated_seq", "updated_at", "$revisions")
    VALUES ('00000000-0000-0000-0000-000000000001', '2026-01-01', '2026-01-01 00:00:00+00',
            '#{c_value}', 1.5, '2026-01-01 00:00:00+00', '2026-01-01 00:00:00+00', 0, '2026-01-01 00:00:00+00', 0, '2026-01-01 00:00:00+00', '{}')
    """

    {:ok, _result} = Connection.query(insert_statement)
  end

  # An enum type standing under another name, as an older naming rule left it, and registered
  # under that name.
  defp rename_enum_type_by_hand(from, to) do
    {:ok, _result} =
      Connection.query(
        ~s(ALTER TYPE "hologram_data".#{Mapper.quote_identifier(from)} RENAME TO #{Mapper.quote_identifier(to)})
      )

    {:ok, _result} =
      Connection.query(
        ~s(UPDATE "hologram_system"."schema_object" SET "name" = $2 WHERE "kind" = 'enum_type' AND "name" = $1),
        [from, to]
      )
  end

  # The columns of the probe table the upgrade steps above create, none when it doesn't exist.
  defp probe_columns do
    statement = """
    SELECT a.attname
    FROM pg_catalog.pg_attribute a
    JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'hologram_system' AND c.relname = 'upgrade_probe'
      AND a.attnum > 0 AND NOT a.attisdropped
    ORDER BY a.attnum
    """

    {:ok, %{rows: rows}} = Connection.query(statement)

    Enum.map(rows, fn [name] -> name end)
  end

  # A claim at layout 1, whatever steps the running Hologram has - the upgrade tests start there.
  defp reconcile_at_layout_1(entity_types) do
    entity_types
    |> reconcile_context()
    |> Map.put(:system_upgrades, [])
    |> reconcile()
  end

  defp set_system_schema_version(version) do
    statement = ~s(UPDATE "hologram_system"."database" SET "system_schema_version" = $1)
    {:ok, _result} = Connection.query(statement, [version])
  end

  # What a reconciliation converges to: the model's schema with the index plan the context leaves to
  # the reconciler, the framework's own lookups'.
  defp expected_schema(context) do
    Schema.from_mapping(context.mapping, IndexPlan.framework_plan(context.mapping))
  end

  defp reconcile_context(entity_types) do
    mapping =
      entity_types
      |> Mapper.derive!([])
      |> Map.drop([RoleGrant])

    Map.put(@context, :mapping, mapping)
  end

  defp reconcile_context_with_grant_store(entity_types) do
    Map.put(@context, :mapping, Mapper.derive!(entity_types, Reflection.list_roles()))
  end

  # Module2's mapping gaining a column "z" with the given default and nullability, and a key
  # over ("c", "z").
  defp key_over_added_column_context(default, null) do
    new_column = %{
      name: "z",
      type: :string,
      sql_type: "text",
      collation: "C",
      enum_values: nil,
      default: default,
      null: null,
      references: nil,
      fk_constraint: nil,
      source: {:attribute, :z}
    }

    [Module2]
    |> reconcile_context()
    |> update_in([:mapping, Module2, :columns], &[new_column | &1])
    |> update_mapping_indexes(Module2, fn indexes ->
      Map.put(indexes, "test_fixtures_entity_module2_c_z_$uidx", %{
        columns: ["c", "z"],
        nulls_distinct: true,
        unique: true
      })
    end)
  end

  # Module2's mapping with a key over ("b", "c").
  defp key_over_b_c_context(entity_types) do
    entity_types
    |> reconcile_context()
    |> update_mapping_indexes(Module2, fn indexes ->
      Map.put(indexes, "test_fixtures_entity_module2_b_c_$uidx", %{
        columns: ["b", "c"],
        nulls_distinct: true,
        unique: true
      })
    end)
  end

  defp filled_duplicate_key_msg do
    ~s(cannot make column "b" on table "test_fixtures_entity_module2" required - ) <>
      ~s{filling its NULLs with the default would make 1 key repeat over ("b", "c") - } <>
      "fix the data, keep the attribute optional: true, or drop the unique declaration"
  end

  # Module2's mapping with two optional string columns "y" and "z", and a key over them.
  defp two_string_key_context do
    new_columns =
      Enum.map([{"y", :y}, {"z", :z}], fn {name, attribute} ->
        %{
          name: name,
          type: :string,
          sql_type: "text",
          collation: "C",
          enum_values: nil,
          default: nil,
          null: true,
          references: nil,
          fk_constraint: nil,
          source: {:attribute, attribute}
        }
      end)

    [Module2]
    |> reconcile_context()
    |> update_in([:mapping, Module2, :columns], &(new_columns ++ &1))
    |> update_mapping_indexes(Module2, fn indexes ->
      Map.put(indexes, "test_fixtures_entity_module2_y_z_$uidx", %{
        columns: ["y", "z"],
        nulls_distinct: true,
        unique: true
      })
    end)
  end

  # Module2's mapping with a unique index over "c".
  defp unique_c_context do
    [Module2]
    |> reconcile_context()
    |> update_mapping_indexes(Module2, fn indexes ->
      Map.put(indexes, "test_fixtures_entity_module2_c_$uidx", %{
        columns: ["c"],
        nulls_distinct: true,
        unique: true
      })
    end)
  end

  defp unique_column_context(null) do
    new_column = %{
      name: "z",
      type: :string,
      sql_type: "text",
      collation: "C",
      enum_values: nil,
      default: nil,
      null: null,
      references: nil,
      fk_constraint: nil,
      source: {:attribute, :z}
    }

    [Module2]
    |> reconcile_context()
    |> update_in([:mapping, Module2, :columns], &[new_column | &1])
    |> update_mapping_indexes(Module2, fn indexes ->
      Map.put(indexes, "test_fixtures_entity_module2_z_$uidx", %{
        columns: ["z"],
        nulls_distinct: true,
        unique: true
      })
    end)
  end

  defp update_mapping_indexes(context, entity_type, fun) do
    update_in(context, [:mapping, entity_type, :indexes], fun)
  end

  defp update_mapping_column(context, entity_type, column_name, fun) do
    update_in(context, [:mapping, entity_type, :columns], fn columns ->
      Enum.map(columns, fn
        %{name: ^column_name} = column -> fun.(column)
        column -> column
      end)
    end)
  end

  describe "backfill_companions!/2" do
    setup do
      drop_hologram_schemas()
      reconcile(reconcile_context([Module2]))

      :ok
    end

    test "fills the sort key an add-column op names" do
      insert_module2_rows(["Łódź"])
      {:ok, _result} = Connection.query(~s(UPDATE #{@module2_table} SET "c_$sort" = NULL))

      op = %{op: :add_column, table: "test_fixtures_entity_module2", column: "c_$sort"}

      assert backfill_companions!([op], reconcile_context([Module2]).mapping) == :ok
      assert module2_sort_pairs() == [["Łódź", "lodz"]]
    end

    test "fills the search key an add-column op names" do
      long_value = String.duplicate("Zurich ", 10)

      insert_module2_rows([long_value])
      {:ok, _result} = Connection.query(~s(UPDATE #{@module2_table} SET "c_$search" = NULL))

      op = %{op: :add_column, table: "test_fixtures_entity_module2", column: "c_$search"}

      assert backfill_companions!([op], reconcile_context([Module2]).mapping) == :ok

      {:ok, %{rows: rows}} = Connection.query(~s(SELECT "c_$search" FROM #{@module2_table}))

      assert rows == [[String.downcase(long_value)]]
    end

    test "passes over an op adding a column that is no companion" do
      insert_module2_rows(["Łódź"])
      {:ok, _result} = Connection.query(~s(UPDATE #{@module2_table} SET "c_$sort" = NULL))

      op = %{op: :add_column, table: "test_fixtures_entity_module2", column: "c"}

      assert backfill_companions!([op], reconcile_context([Module2]).mapping) == :ok
      assert module2_sort_pairs() == [["Łódź", nil]]
    end
  end

  describe "check_system_schema_version!/2" do
    test "returns :ok for a layout at or below the running one" do
      context = %{system_upgrades: [{2, []}]}

      assert check_system_schema_version!(%{system_schema_version: 1}, context) == :ok
      assert check_system_schema_version!(%{system_schema_version: 2}, context) == :ok
    end

    test "raises for a layout above the running one" do
      expected_msg =
        "the configured database's system tables are at layout version 3, from a newer " <>
          "Hologram - this Hologram knows layout versions up to 2 - upgrade Hologram or " <>
          "point the config at another database"

      assert_error RuntimeError, expected_msg, fn ->
        check_system_schema_version!(%{system_schema_version: 3}, %{system_upgrades: [{2, []}]})
      end
    end

    # The migrator checks the layout with a dev context too, and the reset is no way out there.
    test "names no reset for a dev context" do
      expected_msg =
        "the configured database's system tables are at layout version 3, from a newer " <>
          "Hologram - this Hologram knows layout versions up to 2 - upgrade Hologram or " <>
          "point the config at another database"

      assert_error RuntimeError, expected_msg, fn ->
        check_system_schema_version!(
          %{system_schema_version: 3},
          %{env: "dev", system_upgrades: [{2, []}]}
        )
      end
    end
  end

  describe "create_system_tables/0" do
    test "creates the marker, registry, migration, and oplog tables" do
      drop_hologram_schemas()
      {:ok, _result} = Connection.query(~s(CREATE SCHEMA "hologram_system"))

      assert create_system_tables() == :ok

      assert read_marker() == nil
      assert registry() == MapSet.new()

      statement = """
      SELECT c.relname
      FROM pg_catalog.pg_class c
      JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'hologram_system' AND c.relkind = 'r'
      ORDER BY c.relname
      """

      {:ok, %{rows: rows}} = Connection.query(statement)

      assert rows == [
               ["database"],
               ["migration"],
               ["mutation"],
               ["oplog"],
               ["schema_object"],
               ["server_run"]
             ]
    end

    test "names this copy of the database in a view a restore fills again" do
      drop_hologram_schemas()
      {:ok, _result} = Connection.query(~s(CREATE SCHEMA "hologram_system"))

      assert create_system_tables() == :ok

      statement = """
      SELECT c.relispopulated
      FROM pg_catalog.pg_class c
      JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'hologram_system' AND c.relname = 'database_copy' AND c.relkind = 'm'
      """

      assert {:ok, %{rows: [[true]]}} = Connection.query(statement)
    end

    test "gives the oplog the indexes reading it forward and by time need" do
      drop_hologram_schemas()
      {:ok, _result} = Connection.query(~s(CREATE SCHEMA "hologram_system"))

      assert create_system_tables() == :ok

      statement = """
      SELECT c.relname, am.amname, a.attname
      FROM pg_catalog.pg_class c
      JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
      JOIN pg_catalog.pg_am am ON am.oid = c.relam
      JOIN pg_catalog.pg_attribute a ON a.attrelid = c.oid
      WHERE n.nspname = 'hologram_system' AND c.relkind = 'i' AND c.relname LIKE 'oplog%'
      ORDER BY c.relname, a.attnum
      """

      {:ok, %{rows: rows}} = Connection.query(statement)

      # BRIN rather than btree on the timestamp: the table is append-only and never pruned, so
      # its physical order already follows time, and a btree would put its rightmost page in the
      # path of every write to serve a read nothing does yet. Built for the prune that has gone,
      # kept for the history-by-time read that comes next.
      assert rows == [
               ["oplog_inserted_at_$idx", "brin", "inserted_at"],
               ["oplog_pkey", "btree", "seq"]
             ]
    end

    test "gives the oplog the columns the dispatcher and its writers need" do
      drop_hologram_schemas()
      {:ok, _result} = Connection.query(~s(CREATE SCHEMA "hologram_system"))

      assert create_system_tables() == :ok

      statement = """
      SELECT a.attname, format_type(a.atttypid, a.atttypmod), a.attnotnull
      FROM pg_catalog.pg_attribute a
      JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
      JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'hologram_system' AND c.relname = 'oplog' AND a.attnum > 0
      ORDER BY a.attname
      """

      {:ok, %{rows: rows}} = Connection.query(statement)

      assert rows == [
               ["actor_id", "uuid", false],
               ["data", "jsonb", false],
               ["entity_id", "uuid", true],
               ["inserted_at", "timestamp with time zone", true],
               ["model_hash", "text", true],
               ["mutation_ref", "jsonb", false],
               ["old", "jsonb", false],
               ["op", "text", true],
               ["revisions", "jsonb", false],
               ["seq", "bigint", true],
               ["tx", "xid8", true],
               ["type", "text", true]
             ]
    end

    test "gives the mutation table the columns dedup and a refused batch need" do
      drop_hologram_schemas()
      {:ok, _result} = Connection.query(~s(CREATE SCHEMA "hologram_system"))

      assert create_system_tables() == :ok

      statement = """
      SELECT a.attname, format_type(a.atttypid, a.atttypmod), a.attnotnull
      FROM pg_catalog.pg_attribute a
      JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
      JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'hologram_system' AND c.relname = 'mutation' AND a.attnum > 0
      ORDER BY a.attname
      """

      {:ok, %{rows: rows}} = Connection.query(statement)

      # The envelope is filled for a refused batch only: a landed batch's rows are in the oplog
      # under mutation_ref, keyed by the same pair, and a refused batch's rows are nowhere else.
      assert rows == [
               ["actor_id", "uuid", false],
               ["answered_at", "timestamp with time zone", true],
               ["envelope", "jsonb", false],
               ["model_hash", "text", true],
               ["replica_id", "text", true],
               ["result", "jsonb", false],
               ["seq", "bigint", true]
             ]
    end

    test "keys the mutation table by the replica and its sequence number" do
      drop_hologram_schemas()
      {:ok, _result} = Connection.query(~s(CREATE SCHEMA "hologram_system"))

      assert create_system_tables() == :ok

      statement = """
      SELECT c.relname, am.amname, a.attname
      FROM pg_catalog.pg_class c
      JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
      JOIN pg_catalog.pg_am am ON am.oid = c.relam
      JOIN pg_catalog.pg_attribute a ON a.attrelid = c.oid
      WHERE n.nspname = 'hologram_system' AND c.relkind = 'i' AND c.relname LIKE 'mutation%'
      ORDER BY c.relname, a.attnum
      """

      {:ok, %{rows: rows}} = Connection.query(statement)

      # The key IS the dedup: the second arrival of a batch cannot insert its own row, so it
      # blocks on the first and then answers from what the first recorded.
      assert rows == [
               ["mutation_pkey", "btree", "replica_id"],
               ["mutation_pkey", "btree", "seq"]
             ]
    end

    # That two DIFFERENT transactions take different ids is not reachable here - the sandbox
    # runs every test inside one transaction, so these rows share it whatever the default does.
    # What this pins is that the default fires at all and that seq advances.
    test "stamps an oplog row with the transaction that wrote it" do
      drop_hologram_schemas()
      {:ok, _result} = Connection.query(~s(CREATE SCHEMA "hologram_system"))

      assert create_system_tables() == :ok

      insert = """
      INSERT INTO "hologram_system"."oplog" ("op", "type", "entity_id", "model_hash")
      VALUES ('put_entity', 'MyApp.Task', '00000000-0000-4000-8000-000000000001', 'abc123'),
             ('del_entity', 'MyApp.Task', '00000000-0000-4000-8000-000000000002', 'abc123')
      """

      {:ok, _result} = Connection.query(insert)

      {:ok, %{rows: [[writing_tx]]}} = Connection.query("SELECT pg_current_xact_id()")

      select = ~s(SELECT "seq", "tx" FROM "hologram_system"."oplog" ORDER BY "seq")
      {:ok, %{rows: [[first_seq, first_tx], [second_seq, second_tx]]}} = Connection.query(select)

      assert second_seq > first_seq
      assert first_tx == writing_tx
      assert second_tx == writing_tx
    end
  end

  describe "ensure_managed!/1" do
    test "claims a virgin database" do
      drop_hologram_schemas()

      assert ensure_managed!(Map.put(@context, :system_upgrades, [])) == :claimed

      assert read_marker() == %{
               otp_app: "hologram",
               env: "test",
               managed_by: "reconciliation",
               hologram_version: "0.5.0",
               system_schema_version: 1,
               last_reconciled_at: ~U[2026-07-20 12:30:00.000000Z]
             }

      assert registry() == MapSet.new()
    end

    test "claims a virgin database at the running layout" do
      drop_hologram_schemas()

      ensure_managed!(Map.put(@context, :system_upgrades, [{2, []}, {3, []}]))

      assert read_marker().system_schema_version == 3
    end

    test "returns :managed when the marker matches the context" do
      drop_hologram_schemas()
      ensure_managed!(@context)

      assert ensure_managed!(@context) == :managed
    end

    test "raises when the system tables are at a newer layout than the running one" do
      drop_hologram_schemas()
      ensure_managed!(@context)
      set_system_schema_version(3)

      expected_msg =
        "the configured database's system tables are at layout version 3, from a newer " <>
          "Hologram - this Hologram knows layout versions up to 2 - upgrade Hologram or " <>
          "point the config at another database"

      assert_error RuntimeError, expected_msg, fn ->
        ensure_managed!(Map.put(@context, :system_upgrades, [{2, []}]))
      end
    end

    test "names the reset in dev for system tables at a newer layout" do
      drop_hologram_schemas()
      dev_context = %{@context | env: "dev"}
      ensure_managed!(dev_context)
      set_system_schema_version(3)

      expected_msg =
        "the configured database's system tables are at layout version 3, from a newer " <>
          "Hologram - this Hologram knows layout versions up to 2 - upgrade Hologram or " <>
          "point the config at another database" <> @reset_hint

      assert_error RuntimeError, expected_msg, fn ->
        ensure_managed!(Map.put(dev_context, :system_upgrades, [{2, []}]))
      end
    end

    test "names another app ahead of a newer layout" do
      drop_hologram_schemas()
      ensure_managed!(@context)
      set_system_schema_version(3)

      expected_msg =
        "the configured database belongs to app \"hologram\" - " <>
          "the current app is \"other_app\" - point the config at the right database"

      assert_error RuntimeError, expected_msg, fn ->
        @context
        |> Map.merge(%{otp_app: "other_app", system_upgrades: [{2, []}]})
        |> ensure_managed!()
      end
    end

    test "raises when Hologram schemas exist without a marker" do
      drop_hologram_schemas()
      {:ok, _result} = Connection.query(~s(CREATE SCHEMA "hologram_system"))
      {:ok, _result} = Connection.query(~s(CREATE SCHEMA "hologram_data"))

      assert_error RuntimeError, @not_managed_msg, fn ->
        ensure_managed!(@context)
      end
    end

    test "names the reset in dev for Hologram schemas without a marker" do
      drop_hologram_schemas()
      {:ok, _result} = Connection.query(~s(CREATE SCHEMA "hologram_data"))

      assert_error RuntimeError, @not_managed_msg <> @reset_hint, fn ->
        ensure_managed!(%{@context | env: "dev"})
      end
    end

    test "raises when only one Hologram schema exists" do
      drop_hologram_schemas()
      {:ok, _result} = Connection.query(~s(CREATE SCHEMA "hologram_data"))

      assert_error RuntimeError, @not_managed_msg, fn ->
        ensure_managed!(@context)
      end
    end

    test "names the reset in dev for a lone system schema whose marker matches" do
      drop_hologram_schemas()
      dev_context = %{@context | env: "dev"}
      ensure_managed!(dev_context)
      {:ok, _result} = Connection.query(~s(DROP SCHEMA "hologram_data" CASCADE))

      assert_error RuntimeError, @not_managed_msg <> @reset_hint, fn ->
        ensure_managed!(dev_context)
      end
    end

    # The reset refuses these databases too, so it's no way out.
    test "names no reset in dev for a lone system schema whose marker the reset refuses" do
      drop_hologram_schemas()
      ensure_managed!(@context)
      {:ok, _result} = Connection.query(~s(DROP SCHEMA "hologram_data" CASCADE))

      assert_raise RuntimeError, ~r/ - point the config at the right database$/, fn ->
        ensure_managed!(%{@context | otp_app: "other_app", env: "dev"})
      end

      assert_raise RuntimeError, ~r/ - the config points at another env's database$/, fn ->
        ensure_managed!(%{@context | env: "dev"})
      end

      write_marker(%{read_marker() | env: "dev", managed_by: "migrations"})

      assert_raise RuntimeError, ~r/ - schema reconciliation never touches it$/, fn ->
        ensure_managed!(%{@context | env: "dev"})
      end
    end

    test "raises when the marker row is missing" do
      drop_hologram_schemas()
      ensure_managed!(@context)
      {:ok, _result} = Connection.query(~s(DELETE FROM "hologram_system"."database"))

      assert_error RuntimeError, @not_managed_msg, fn ->
        ensure_managed!(@context)
      end
    end

    test "raises when the marker belongs to another app" do
      drop_hologram_schemas()
      ensure_managed!(@context)

      expected_msg =
        "the configured database belongs to app \"hologram\" - " <>
          "the current app is \"other_app\" - point the config at the right database"

      assert_error RuntimeError, expected_msg, fn ->
        ensure_managed!(%{@context | otp_app: "other_app"})
      end
    end

    test "raises when the marker belongs to another env" do
      drop_hologram_schemas()
      ensure_managed!(@context)

      expected_msg =
        "the configured database belongs to the \"test\" env - " <>
          "the current env is \"dev\" - the config points at another env's database"

      assert_error RuntimeError, expected_msg, fn ->
        ensure_managed!(%{@context | env: "dev"})
      end
    end

    # The reset refuses these databases too, so it's no way out.
    test "names no reset in dev for another app's, another env's or a migration-managed database" do
      drop_hologram_schemas()
      ensure_managed!(@context)

      assert_raise RuntimeError, ~r/ - point the config at the right database$/, fn ->
        ensure_managed!(%{@context | otp_app: "other_app", env: "dev"})
      end

      assert_raise RuntimeError, ~r/ - the config points at another env's database$/, fn ->
        ensure_managed!(%{@context | env: "dev"})
      end

      drop_hologram_schemas()
      dev_context = %{@context | env: "dev"}
      ensure_managed!(dev_context)
      write_marker(%{read_marker() | managed_by: "migrations"})

      assert_raise RuntimeError, ~r/ - schema reconciliation never touches it$/, fn ->
        ensure_managed!(dev_context)
      end
    end

    test "raises when the database is managed by migrations" do
      drop_hologram_schemas()
      ensure_managed!(@context)
      write_marker(%{read_marker() | managed_by: "migrations"})

      expected_msg =
        "the configured database is managed by migrations - " <>
          "schema reconciliation never touches it"

      assert_error RuntimeError, expected_msg, fn ->
        ensure_managed!(@context)
      end
    end
  end

  describe "log_system_upgrades/1" do
    test "logs one info line per version, in order" do
      log = capture_info_log(fn -> assert log_system_upgrades([2, 3]) == :ok end)

      assert Regex.scan(
               ~r/\[info\] Hologram: upgraded the system tables to layout version (\d+)/,
               log,
               capture: :all_but_first
             ) == [["2"], ["3"]]
    end
  end

  describe "pending_system_upgrades/1" do
    setup do
      drop_hologram_schemas()
      ensure_managed!(Map.put(@context, :system_upgrades, []))
      :ok
    end

    test "returns every step above the database's layout, in order" do
      context = %{system_upgrades: [@create_probe_step, @alter_probe_step]}

      assert pending_system_upgrades(context) == [@create_probe_step, @alter_probe_step]

      set_system_schema_version(2)

      assert pending_system_upgrades(context) == [@alter_probe_step]
    end

    test "returns none for a database at the running layout" do
      set_system_schema_version(3)

      assert pending_system_upgrades(%{system_upgrades: [@create_probe_step, @alter_probe_step]}) ==
               []
    end
  end

  describe "read_marker/0" do
    test "returns nil when no marker has been written" do
      {:ok, _result} = Connection.query(~s(DELETE FROM "hologram_system"."database"))

      assert read_marker() == nil
    end

    test "returns the written marker" do
      write_marker(@marker)

      assert read_marker() == @marker
    end
  end

  describe "reconcile/1" do
    setup do
      drop_hologram_schemas()
      :ok
    end

    test "claims a virgin database and converges it to the mapping" do
      context = reconcile_context([Module1])

      result = reconcile(context)

      assert result.status == :claimed
      assert Introspection.schema() == expected_schema(context)
      assert {:table, "", "test_fixtures_entity_module1"} in registry()
      assert read_marker().last_reconciled_at == @context.timestamp
    end

    test "refreshes the marker and leaves its layout version as it was" do
      reconcile(reconcile_context([Module1]))
      set_system_schema_version(0)

      context =
        [Module1]
        |> reconcile_context()
        |> Map.merge(%{
          hologram_version: "0.6.0",
          timestamp: ~U[2026-07-21 08:00:00.000000Z],
          system_upgrades: []
        })

      reconcile(context)

      assert read_marker() == %{
               @marker
               | hologram_version: "0.6.0",
                 system_schema_version: 0,
                 last_reconciled_at: ~U[2026-07-21 08:00:00.000000Z]
             }
    end

    test "upgrades the system tables of a database at an older layout, step by step" do
      reconcile_at_layout_1([Module1])

      context =
        [Module1]
        |> reconcile_context()
        |> Map.put(:system_upgrades, [@create_probe_step, @alter_probe_step])

      log = capture_info_log(fn -> reconcile(context) end)

      assert probe_columns() == ["id", "note"]
      assert read_marker().system_schema_version == 3

      assert Regex.scan(~r/upgraded the system tables to layout version (\d+)/, log,
               capture: :all_but_first
             ) == [["2"], ["3"]]
    end

    test "runs only the upgrade steps above the database's layout" do
      reconcile_at_layout_1([Module1])

      [Module1]
      |> reconcile_context()
      |> Map.put(:system_upgrades, [@create_probe_step])
      |> reconcile()

      log =
        capture_info_log(fn ->
          [Module1]
          |> reconcile_context()
          |> Map.put(:system_upgrades, [@create_probe_step, @alter_probe_step])
          |> reconcile()
        end)

      assert probe_columns() == ["id", "note"]
      assert read_marker().system_schema_version == 3
      refute log =~ "layout version 2"
      assert log =~ "upgraded the system tables to layout version 3"
    end

    test "claims a virgin database at the running layout without running a step" do
      [Module1]
      |> reconcile_context()
      |> Map.put(:system_upgrades, [@create_probe_step])
      |> reconcile()

      assert probe_columns() == []
      assert read_marker().system_schema_version == 2
    end

    test "rolls the upgrade back with a refused reconciliation, and logs none" do
      reconcile_at_layout_1([Module1])

      {:ok, _result} = Connection.query(~s{CREATE TABLE "hologram_data"."alien" ("x" int8)})

      context =
        [Module1]
        |> reconcile_context()
        |> Map.put(:system_upgrades, [@create_probe_step])

      expected_msg =
        ~s(unknown table "alien" in the hologram_data schema - ) <>
          "this schema is model-managed - move the object to another schema or remove it"

      log =
        capture_info_log(fn ->
          assert_error RuntimeError, expected_msg, fn -> reconcile(context) end
        end)

      assert probe_columns() == []
      assert read_marker().system_schema_version == 1
      refute log =~ "upgraded the system tables"
    end

    test "returns no ops when the schema already matches" do
      context = reconcile_context([Module1])
      reconcile(context)

      result = reconcile(context)

      assert result.status == :managed
      assert result.ops == []
    end

    test "converges relationships, join tables, and indexes" do
      context = reconcile_context([Module1, Module2, Module3])

      reconcile(context)

      assert Introspection.schema() == expected_schema(context)
    end

    test "builds the indexes of the plan the context carries, and drops one it no longer names" do
      context = reconcile_context([Module1, Module2, Module3])
      table = "test_fixtures_entity_module3"
      wide = %{table: table, eq: MapSet.new(["b_id", "c_id"]), range: nil, order: []}

      plan_with_wide =
        context.mapping
        |> IndexPlan.framework_needs()
        |> Enum.concat([wide])
        |> IndexPlan.select(context.mapping)

      reconcile(Map.put(context, :plan, plan_with_wide))

      # The wider index serves the lookup by b_id the framework needs, so b_id gets no index of its
      # own, while c_id, which it doesn't lead with, keeps one.
      assert Map.keys(Introspection.schema().tables[table].indexes) == [
               "test_fixtures_entity_module3_b_id_c_id_$idx",
               "test_fixtures_entity_module3_c_id_$idx"
             ]

      ExUnit.CaptureLog.capture_log(fn -> reconcile(context) end)

      assert Introspection.schema() == expected_schema(context)
    end

    test "converges a unique attribute's index" do
      context = reconcile_context([Module19])

      reconcile(context)

      assert Introspection.schema() == expected_schema(context)
    end

    test "converges the index of each key declared with unique" do
      context = reconcile_context([Module1, Module52])

      reconcile(context)

      assert Introspection.schema() == expected_schema(context)

      assert Introspection.schema().tables["test_fixtures_entity_module52"].indexes[
               "test_fixtures_entity_module52_workspace_id_slug_$uidx"
             ] == %{columns: ["workspace_id", "slug"], nulls_distinct: true, unique: true}
    end

    test "renames an index standing under an old name instead of rebuilding it" do
      context = reconcile_context([Module19])
      reconcile(context)

      table = "test_fixtures_entity_module19"
      old_name = "test_fixtures_entity_module19_old_$uidx"
      new_name = "test_fixtures_entity_module19_slug_$uidx"

      rename_index_by_hand(table, new_name, old_name, true)

      result = reconcile(context)

      assert result.ops == [%{op: :rename_index, table: table, from: old_name, to: new_name}]
      assert Introspection.schema() == expected_schema(context)

      assert {:index, table, new_name} in registry()
      refute {:index, table, old_name} in registry()
    end

    test "leaves one registry row for a renamed index whatever stale rows stood before" do
      context = reconcile_context([Module19])
      reconcile(context)

      table = "test_fixtures_entity_module19"
      old_name = "test_fixtures_entity_module19_old_$uidx"
      new_name = "test_fixtures_entity_module19_slug_$uidx"

      rename_index_by_hand(table, new_name, old_name, true)

      insert_statement = """
      INSERT INTO "hologram_system"."schema_object" ("kind", "parent", "name")
      VALUES ('index', $1, $2), ('index', 'elsewhere', $3)
      """

      {:ok, _result} = Connection.query(insert_statement, [table, new_name, old_name])

      reconcile(context)

      index_rows =
        Enum.filter(registry(), fn {kind, _parent, name} ->
          kind == :index and name in [old_name, new_name]
        end)

      assert index_rows == [{:index, table, new_name}]
    end

    test "raises for an unregistered index the model's definition matches" do
      context = reconcile_context([Module19])
      reconcile(context)

      table = "test_fixtures_entity_module19"
      hand_made_name = "hand_made_slug_index"

      rename_index_by_hand(
        table,
        "test_fixtures_entity_module19_slug_$uidx",
        hand_made_name,
        false
      )

      expected_msg =
        ~s(unknown index "hand_made_slug_index" in the hologram_data schema - ) <>
          "this schema is model-managed - move the object to another schema or remove it"

      assert_error RuntimeError, expected_msg, fn -> reconcile(context) end
    end

    test "converges an attribute that stops being unique" do
      reconcile(reconcile_context([Module19]))

      context =
        [Module19]
        |> reconcile_context()
        |> update_mapping_indexes(Module19, fn indexes ->
          Map.reject(indexes, fn {_name, index} -> index.unique end)
        end)

      reconcile(context)

      assert Introspection.schema() == expected_schema(context)
    end

    test "converges a unique to-one's reference index" do
      context = reconcile_context([Module26, Module27])

      reconcile(context)

      assert Introspection.schema() == expected_schema(context)

      assert channel_indexes() == %{
               "test_fixtures_entity_module27_channel_id_$uidx" => %{
                 columns: ["channel_id"],
                 nulls_distinct: true,
                 unique: true
               }
             }
    end

    test "converges a to-one that becomes unique" do
      reconcile(non_unique_channel_context())

      context = reconcile_context([Module26, Module27])

      reconcile(context)

      assert Introspection.schema() == expected_schema(context)

      assert channel_indexes() == %{
               "test_fixtures_entity_module27_channel_id_$uidx" => %{
                 columns: ["channel_id"],
                 nulls_distinct: true,
                 unique: true
               }
             }
    end

    test "converges a to-one that stops being unique" do
      reconcile(reconcile_context([Module26, Module27]))

      assert Map.keys(channel_indexes()) == ["test_fixtures_entity_module27_channel_id_$uidx"]

      context = non_unique_channel_context()

      reconcile(context)

      assert Introspection.schema() == expected_schema(context)

      assert channel_indexes() == %{
               "test_fixtures_entity_module27_channel_id_$idx" => %{
                 columns: ["channel_id"],
                 nulls_distinct: true,
                 unique: false
               }
             }
    end

    test "converges a new required unique column on an empty table" do
      reconcile(reconcile_context([Module2]))

      context = unique_column_context(false)

      reconcile(context)

      assert Introspection.schema() == expected_schema(context)
    end

    test "converges a new optional unique column on a table with rows" do
      reconcile(reconcile_context([Module2]))
      insert_module2_rows(["abc", "def"])

      context = unique_column_context(true)

      reconcile(context)

      select_statement =
        ~s(SELECT "z" FROM "hologram_data"."test_fixtures_entity_module2" ORDER BY "c")

      {:ok, %{rows: rows}} = Connection.query(select_statement)

      assert rows == [[nil], [nil]]
      assert Introspection.schema() == expected_schema(context)
    end

    test "converges enum types" do
      context = reconcile_context([Module4])

      reconcile(context)

      assert Introspection.schema() == expected_schema(context)
    end

    test "converges a role type with no values and finds it converged on the next run" do
      context =
        Reflection.list_entities()
        |> reconcile_context_with_grant_store()
        |> update_mapping_column(RoleGrant, "role", &%{&1 | enum_values: []})

      reconcile(context)

      assert Introspection.schema() == expected_schema(context)

      result = reconcile(context)

      assert result.ops == []
      assert Introspection.schema() == expected_schema(context)
    end

    test "converges additive model changes" do
      reconcile(reconcile_context([Module1]))
      context = reconcile_context([Module1, Module4])

      result = reconcile(context)

      assert result.status == :managed
      assert Introspection.schema() == expected_schema(context)
    end

    test "converges destructive model changes and cleans the registry" do
      reconcile(reconcile_context([Module1, Module4]))
      context = reconcile_context([Module1])

      reconcile(context)

      assert Introspection.schema() == expected_schema(context)
      refute {:table, "", "test_fixtures_entity_module4"} in registry()
      refute {:enum_type, "", "test_fixtures_entity_module4_c_$enum"} in registry()
    end

    test "converges a data-dependent type change when the rows allow it" do
      reconcile(reconcile_context([Module2]))
      insert_module2_row("NULL", "' 123 '")

      context =
        [Module2]
        |> reconcile_context()
        |> update_mapping_column(Module2, "c", &%{&1 | sql_type: "int8", collation: nil})

      reconcile(context)

      assert Introspection.schema() == expected_schema(context)
    end

    test "converges an enum value removal when no rows hold it" do
      reconcile(reconcile_context([Module4]))

      context =
        [Module4]
        |> reconcile_context()
        |> update_mapping_column(Module4, "c", &%{&1 | enum_values: ["x"]})

      reconcile(context)

      assert Introspection.schema() == expected_schema(context)
    end

    test "fills NULLs with the declared default when making a column required" do
      reconcile(reconcile_context([Module2]))
      insert_module2_row("NULL", "'abc'")

      context =
        [Module2]
        |> reconcile_context()
        |> update_mapping_column(Module2, "b", &%{&1 | default: 42, null: false})

      reconcile(context)

      select_statement =
        ~s(SELECT "b" FROM "hologram_data"."test_fixtures_entity_module2")

      {:ok, %{rows: rows}} = Connection.query(select_statement)

      assert rows == [[42]]
      assert Introspection.schema() == expected_schema(context)
    end

    test "fills the sort and search keys of a string it fills when making the string required" do
      optional_context =
        [Module2]
        |> reconcile_context()
        |> update_mapping_column(Module2, "c", &%{&1 | null: true})

      reconcile(optional_context)
      insert_module2_row("NULL", "NULL")

      long_default = "Abc" <> String.duplicate("x", 70)

      context =
        [Module2]
        |> reconcile_context()
        |> update_mapping_column(Module2, "c", &%{&1 | default: long_default})

      reconcile(context)

      select_statement =
        ~s(SELECT "c", "c_$sort", "c_$search" FROM "hologram_data"."test_fixtures_entity_module2")

      {:ok, %{rows: rows}} = Connection.query(select_statement)

      assert rows == [
               [long_default, SortKey.compute(long_default), SortKey.search_key(long_default)]
             ]
    end

    test "fills existing rows with the declared default when adding a required column" do
      reconcile(reconcile_context([Module2]))
      insert_module2_row("NULL", "'abc'")

      new_column = %{
        name: "z",
        type: :integer,
        sql_type: "int8",
        collation: nil,
        enum_values: nil,
        default: 7,
        null: false,
        references: nil,
        fk_constraint: nil,
        source: {:attribute, :z}
      }

      context =
        update_in(reconcile_context([Module2]), [:mapping, Module2, :columns], fn columns ->
          [new_column | columns]
        end)

      reconcile(context)

      select_statement =
        ~s(SELECT "z" FROM "hologram_data"."test_fixtures_entity_module2")

      {:ok, %{rows: rows}} = Connection.query(select_statement)

      assert rows == [[7]]
      assert Introspection.schema() == expected_schema(context)
    end

    test "fills the sort-key companion of a column it adds" do
      reconcile(reconcile_context([Module2]))
      insert_module2_rows(["Zürich", "apple"])
      {:ok, _result} = Connection.query(~s(ALTER TABLE #{@module2_table} DROP COLUMN "c_$sort"))

      context = reconcile_context([Module2])

      reconcile(context)

      assert module2_sort_pairs() == [["apple", "apple"], ["Zürich", "zurich"]]
      assert Introspection.schema() == expected_schema(context)
    end

    test "fills a companion whose source is cast to text in the same run" do
      reconcile(reconcile_context([Module2]))
      insert_module2_rows(["10", "9"])

      {:ok, _result} = Connection.query(~s(ALTER TABLE #{@module2_table} DROP COLUMN "c_$sort"))

      {:ok, _result} =
        Connection.query(
          ~s(ALTER TABLE #{@module2_table} ALTER COLUMN "c" TYPE int8 USING "c"::int8)
        )

      context = reconcile_context([Module2])

      reconcile(context)

      assert module2_sort_pairs() == [["10", "10"], ["9", "9"]]
    end

    test "logs each destructive action after the run" do
      reconcile(reconcile_context([Module1, Module4]))
      context = reconcile_context([Module1])

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          reconcile(context)
        end)

      assert log =~
               ~s(Hologram: schema reconciliation dropped table "test_fixtures_entity_module4")

      assert log =~
               ~s(Hologram: schema reconciliation dropped enum type "test_fixtures_entity_module4_c_$enum")
    end

    test "renames a join table standing under an old name, keeping its links" do
      context = reconcile_context([Module1, Module2, Module3])
      reconcile(context)
      insert_module3_link()

      old_name = "test_fixtures_entity_module3_old_$join"
      rename_join_table_by_hand(old_name, true)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert reconcile(context).ops == [
                   %{op: :rename_table, from: old_name, to: @module3_join_table}
                 ]
        end)

      assert log =~
               ~s(Hologram: schema reconciliation renamed join table "#{old_name}" to "#{@module3_join_table}", ) <>
                 "keeping its links. If relationship :a of Hologram.Test.Fixtures.Entity.Module3 " <>
                 "is a new relationship, not a rename, delete its links or reset the database"

      assert Introspection.schema() == expected_schema(context)

      {:ok, %{rows: rows}} =
        Connection.query(
          ~s|SELECT count(*) FROM "hologram_data".#{Mapper.quote_identifier(@module3_join_table)}|
        )

      assert rows == [[1]]

      registry = registry()

      assert {:table, "", @module3_join_table} in registry
      assert {:column, @module3_join_table, "source_id"} in registry
      refute Enum.any?(registry, fn {_kind, parent, name} -> old_name in [parent, name] end)
    end

    test "renames a join table with its constraints, registry included" do
      reconcile(reconcile_context([Module1, Module2, Module3]))
      insert_module3_link()

      new_name = "test_fixtures_entity_module3_z_$join"

      context =
        [Module1, Module2, Module3]
        |> reconcile_context()
        |> update_in([:mapping, Module3, :join_tables], fn [join_table] ->
          [
            %{
              join_table
              | name: new_name,
                pk_constraint: "#{new_name}_$pk",
                source_fk_constraint: "#{new_name}_source_id_$fk",
                target_fk_constraint: "#{new_name}_target_id_$fk"
            }
          ]
        end)

      ExUnit.CaptureLog.capture_log(fn ->
        op_kinds = Enum.map(reconcile(context).ops, & &1.op)

        assert op_kinds == [
                 :rename_table,
                 :rename_constraint,
                 :rename_constraint,
                 :rename_constraint
               ]
      end)

      assert Introspection.schema() == expected_schema(context)

      {:ok, %{rows: rows}} =
        Connection.query(
          ~s|SELECT count(*) FROM "hologram_data".#{Mapper.quote_identifier(new_name)}|
        )

      assert rows == [[1]]

      registry_rows =
        registry()
        |> Enum.filter(fn {_kind, parent, name} -> new_name in [parent, name] end)
        |> Enum.sort()

      assert registry_rows == [
               {:column, new_name, "source_id"},
               {:column, new_name, "target_id"},
               {:constraint, new_name, "#{new_name}_$pk"},
               {:constraint, new_name, "#{new_name}_source_id_$fk"},
               {:constraint, new_name, "#{new_name}_target_id_$fk"},
               {:index, new_name,
                "test_fixtures_entity_module3_a_$join_target_id_source_id_$idx"},
               {:table, "", new_name}
             ]
    end

    test "renames a join table whatever stale registry rows stood under its new name" do
      context = reconcile_context([Module1, Module2, Module3])
      reconcile(context)

      old_name = "test_fixtures_entity_module3_old_$join"
      rename_join_table_by_hand(old_name, true)

      insert_statement = """
      INSERT INTO "hologram_system"."schema_object" ("kind", "parent", "name")
      VALUES ('table', '', $1), ('column', $1, 'source_id')
      """

      {:ok, _result} = Connection.query(insert_statement, [@module3_join_table])

      ExUnit.CaptureLog.capture_log(fn -> reconcile(context) end)

      registry_rows =
        Enum.filter(registry(), fn {_kind, parent, name} ->
          @module3_join_table in [parent, name] or old_name in [parent, name]
        end)

      assert Enum.sort(registry_rows) == [
               {:column, @module3_join_table, "source_id"},
               {:column, @module3_join_table, "target_id"},
               {:constraint, @module3_join_table, "#{@module3_join_table}_$pk"},
               {:constraint, @module3_join_table, "#{@module3_join_table}_source_id_$fk"},
               {:constraint, @module3_join_table, "#{@module3_join_table}_target_id_$fk"},
               {:index, @module3_join_table, "#{@module3_join_table}_target_id_source_id_$idx"},
               {:table, "", @module3_join_table}
             ]
    end

    test "raises for an unregistered join-shaped table the model's ends match" do
      context = reconcile_context([Module1, Module2, Module3])
      reconcile(context)

      rename_join_table_by_hand("hand_made_links", false)

      expected_msg =
        ~s(unknown table "hand_made_links" in the hologram_data schema - ) <>
          "this schema is model-managed - move the object to another schema or remove it"

      assert_error RuntimeError, expected_msg, fn -> reconcile(context) end
    end

    test "raises for a hand-created table in hologram_data" do
      reconcile(reconcile_context([Module1]))

      {:ok, _result} = Connection.query(~s{CREATE TABLE "hologram_data"."alien" ("x" int8)})

      expected_msg =
        ~s(unknown table "alien" in the hologram_data schema - ) <>
          "this schema is model-managed - move the object to another schema or remove it"

      assert_error RuntimeError, expected_msg, fn ->
        reconcile(reconcile_context([Module1]))
      end
    end

    test "names the reset in dev for a hand-created table in hologram_data" do
      context = %{reconcile_context([Module1]) | env: "dev"}
      reconcile(context)

      {:ok, _result} = Connection.query(~s{CREATE TABLE "hologram_data"."alien" ("x" int8)})

      expected_msg =
        ~s(unknown table "alien" in the hologram_data schema - ) <>
          "this schema is model-managed - move the object to another schema or remove it" <>
          @reset_hint

      assert_error RuntimeError, expected_msg, fn ->
        reconcile(context)
      end
    end

    test "names the reset in dev for a failed system table upgrade" do
      context = %{reconcile_context([Module1]) | env: "dev"}
      ensure_managed!(Map.put(context, :system_upgrades, []))

      expected_msg =
        ~r/^upgrading the system tables to layout version 2 failed - .*division by zero#{Regex.escape(@reset_hint)}$/

      assert_raise RuntimeError, expected_msg, fn ->
        reconcile(Map.put(context, :system_upgrades, [{2, ["SELECT 1 / 0"]}]))
      end
    end

    test "raises for a hand-added column on a managed table" do
      reconcile(reconcile_context([Module1]))

      alter_statement =
        ~s(ALTER TABLE "hologram_data"."test_fixtures_entity_module1" ADD COLUMN "extra" int8)

      {:ok, _result} = Connection.query(alter_statement)

      expected_msg =
        ~s(unknown column "extra" on table "test_fixtures_entity_module1" ) <>
          "in the hologram_data schema - this schema is model-managed - " <>
          "move the object to another schema or remove it"

      assert_error RuntimeError, expected_msg, fn ->
        reconcile(reconcile_context([Module1]))
      end
    end

    test "raises for an unsupported type change" do
      reconcile(reconcile_context([Module2]))

      context =
        [Module2]
        |> reconcile_context()
        |> update_mapping_column(Module2, "c", &%{&1 | sql_type: "boolean", collation: nil})

      expected_msg =
        ~s(changing column "c" on table "test_fixtures_entity_module2" ) <>
          "from text to boolean is not supported - " <>
          "remove the attribute and re-add it with the new type"

      assert_error RuntimeError, expected_msg, fn ->
        reconcile(context)
      end
    end

    test "raises for a data-dependent type change blocked by existing rows" do
      reconcile(reconcile_context([Module2]))
      insert_module2_row("NULL", "'abc'")

      context =
        [Module2]
        |> reconcile_context()
        |> update_mapping_column(Module2, "c", &%{&1 | sql_type: "int8", collation: nil})

      expected_msg =
        ~s(1 row in "test_fixtures_entity_module2"."c" ) <>
          "cannot convert from text to int8 - " <>
          "fix the data or remove the attribute and re-add it with the new type"

      assert_error RuntimeError, expected_msg, fn ->
        reconcile(context)
      end
    end

    test "raises when a type change makes rows repeat a unique value" do
      reconcile(unique_c_context())
      insert_module2_rows(["1", "01"])

      context =
        update_mapping_column(
          unique_c_context(),
          Module2,
          "c",
          &%{&1 | sql_type: "int8", collation: nil}
        )

      expected_msg =
        ~s(cannot change column "c" on table "test_fixtures_entity_module2" ) <>
          ~s{from text to int8 - 1 key over ("c") would repeat once converted - } <>
          "fix the data, or drop the unique declaration before changing the type"

      assert_error RuntimeError, expected_msg, fn ->
        reconcile(context)
      end

      assert Introspection.schema() == expected_schema(unique_c_context())
    end

    test "raises when a type change makes rows repeat a key" do
      reconcile(key_over_b_c_context([Module2]))
      insert_module2_rows(["1", "1.0", "2"])

      {:ok, _result} =
        Connection.query(~s(UPDATE "hologram_data"."test_fixtures_entity_module2" SET "b" = 5))

      context =
        [Module2]
        |> key_over_b_c_context()
        |> update_mapping_column(Module2, "c", &%{&1 | sql_type: "float8", collation: nil})

      expected_msg =
        ~s(cannot change column "c" on table "test_fixtures_entity_module2" ) <>
          ~s{from text to float8 - 1 key over ("b", "c") would repeat once converted - } <>
          "fix the data, or drop the unique declaration before changing the type"

      assert_error RuntimeError, expected_msg, fn ->
        reconcile(context)
      end
    end

    # The index does not stand when the type changes, so the refusal is the index build's.
    test "leaves rows a type change makes repeat a key the run builds to the index build" do
      reconcile(reconcile_context([Module2]))
      insert_module2_rows(["1", "01"])

      context =
        update_mapping_column(
          unique_c_context(),
          Module2,
          "c",
          &%{&1 | sql_type: "int8", collation: nil}
        )

      expected_msg =
        ~s{found 1 duplicate key in "test_fixtures_entity_module2" over ("c") - } <>
          "a unique index cannot be built while rows repeat a key - " <>
          "update the rows or drop the unique declaration"

      assert_error RuntimeError, expected_msg, fn ->
        reconcile(context)
      end
    end

    # int8 to float8 has no row check of its own: every value converts, and two past 2^53
    # convert to one.
    test "raises when an integer to float change makes rows repeat a key" do
      reconcile(key_over_b_c_context([Module2]))
      insert_module2_rows(["abc", "abc"])

      Enum.each([{1, 9_007_199_254_740_992}, {2, 9_007_199_254_740_993}], fn {index, value} ->
        {:ok, _result} =
          Connection.query("""
          UPDATE "hologram_data"."test_fixtures_entity_module2" SET "b" = #{value}
          WHERE "id" = '00000000-0000-0000-0000-00000000000#{index}'
          """)
      end)

      context =
        [Module2]
        |> key_over_b_c_context()
        |> update_mapping_column(Module2, "b", &%{&1 | sql_type: "float8"})

      expected_msg =
        ~s(cannot change column "b" on table "test_fixtures_entity_module2" ) <>
          ~s{from int8 to float8 - 1 key over ("b", "c") would repeat once converted - } <>
          "fix the data, or drop the unique declaration before changing the type"

      assert_error RuntimeError, expected_msg, fn ->
        reconcile(context)
      end
    end

    # Neither change alone makes the rows repeat the key: ("1", "01") and ("01", "1") do
    # once both columns are integers. Each change asks against the rows as the one before
    # left them.
    test "raises when two type changes together make rows repeat a key" do
      context = two_string_key_context()

      reconcile(context)

      Enum.each([{1, "1", "01"}, {2, "01", "1"}], fn {index, y_value, z_value} ->
        {:ok, _result} =
          Connection.query("""
          INSERT INTO "hologram_data"."test_fixtures_entity_module2"
            ("id", "a", "b", "c", "y", "z", "created_at", "server_created_at", "server_created_seq", "server_updated_at", "server_updated_seq", "updated_at", "$revisions")
          VALUES ('00000000-0000-0000-0000-00000000000#{index}', TRUE, NULL, 'abc',
                  '#{y_value}', '#{z_value}',
                  '2026-01-01 00:00:00+00', '2026-01-01 00:00:00+00', 0, '2026-01-01 00:00:00+00', 0, '2026-01-01 00:00:00+00', '{}')
          """)
      end)

      changed_context =
        context
        |> update_mapping_column(Module2, "y", &%{&1 | sql_type: "int8", collation: nil})
        |> update_mapping_column(Module2, "z", &%{&1 | sql_type: "int8", collation: nil})

      expected_msg =
        ~s(cannot change column "z" on table "test_fixtures_entity_module2" ) <>
          ~s{from text to int8 - 1 key over ("y", "z") would repeat once converted - } <>
          "fix the data, or drop the unique declaration before changing the type"

      assert_error RuntimeError, expected_msg, fn ->
        reconcile(changed_context)
      end
    end

    test "changes the type of a key's column when no rows repeat the key once converted" do
      reconcile(key_over_b_c_context([Module2]))
      insert_module2_rows(["1", "01"])

      {:ok, _result} =
        Connection.query("""
        UPDATE "hologram_data"."test_fixtures_entity_module2" SET "b" = 5
        WHERE "id" = '00000000-0000-0000-0000-000000000001'
        """)

      context =
        [Module2]
        |> key_over_b_c_context()
        |> update_mapping_column(Module2, "c", &%{&1 | sql_type: "int8", collation: nil})

      reconcile(context)

      assert Introspection.schema() == expected_schema(context)
    end

    test "raises when making a column required while rows hold NULL" do
      reconcile(reconcile_context([Module2]))
      insert_module2_row("NULL", "'abc'")

      context =
        [Module2]
        |> reconcile_context()
        |> update_mapping_column(Module2, "b", &%{&1 | null: false})

      expected_msg =
        ~s(cannot make column "b" on table "test_fixtures_entity_module2" required - ) <>
          "found 1 row with NULL - " <>
          "declare default: <value>, keep the attribute optional: true, or fix the data"

      assert_error RuntimeError, expected_msg, fn ->
        reconcile(context)
      end
    end

    test "raises when adding a required column to a table with rows" do
      reconcile(reconcile_context([Module2]))
      insert_module2_row("NULL", "'abc'")

      new_column = %{
        name: "z",
        type: :integer,
        sql_type: "int8",
        collation: nil,
        enum_values: nil,
        default: nil,
        null: false,
        references: nil,
        fk_constraint: nil,
        source: {:attribute, :z}
      }

      context =
        update_in(reconcile_context([Module2]), [:mapping, Module2, :columns], fn columns ->
          [new_column | columns]
        end)

      expected_msg =
        ~s(cannot add required column "z" to table "test_fixtures_entity_module2" - ) <>
          "1 existing row would have no value - " <>
          "declare default: <value>, make the attribute optional: true, or clear the rows"

      assert_error RuntimeError, expected_msg, fn ->
        reconcile(context)
      end
    end

    # The guard's refusals are hinted apart from converge!/1's, so a boot names the reset once.
    test "names the reset once in dev for Hologram schemas without a marker" do
      {:ok, _result} = Connection.query(~s(CREATE SCHEMA "hologram_data"))

      assert_error RuntimeError, @not_managed_msg <> @reset_hint, fn ->
        reconcile(%{reconcile_context([Module1]) | env: "dev"})
      end
    end

    test "names the reset in dev for a primary key edited by hand" do
      context = %{reconcile_context([Module1]) | env: "dev"}
      reconcile(context)

      {:ok, _result} =
        Connection.query("""
        ALTER TABLE "hologram_data"."test_fixtures_entity_module1"
          DROP CONSTRAINT "test_fixtures_entity_module1_$pk",
          ADD CONSTRAINT "test_fixtures_entity_module1_$pk" PRIMARY KEY ("id", "created_at")
        """)

      expected_msg =
        ~s(primary key columns mismatch on table "test_fixtures_entity_module1" ) <>
          ~s{(actual: ["id", "created_at"], target: ["id"]) - } <>
          "no derivable schema can produce this, the database was edited by hand" <> @reset_hint

      assert_error RuntimeError, expected_msg, fn ->
        reconcile(context)
      end
    end

    # Only refusals raise RuntimeError, so a failing statement is left as it is.
    test "names no reset in dev for an error that isn't a refusal" do
      dev_context = %{reconcile_context([Module2]) | env: "dev"}

      context =
        update_in(dev_context, [:mapping, Module2, :columns], fn [column | columns] ->
          [%{column | sql_type: "no_such_type"} | columns]
        end)

      error = assert_raise MatchError, fn -> reconcile(context) end

      refute Exception.message(error) =~ "holo.db.reset"
    end

    test "names the reset in dev for a preflight refusal" do
      dev_context = %{reconcile_context([Module2]) | env: "dev"}
      reconcile(dev_context)
      insert_module2_row("NULL", "'abc'")

      new_column = %{
        name: "z",
        type: :integer,
        sql_type: "int8",
        collation: nil,
        enum_values: nil,
        default: nil,
        null: false,
        references: nil,
        fk_constraint: nil,
        source: {:attribute, :z}
      }

      context =
        update_in(dev_context, [:mapping, Module2, :columns], fn columns ->
          [new_column | columns]
        end)

      expected_msg =
        ~s(cannot add required column "z" to table "test_fixtures_entity_module2" - ) <>
          "1 existing row would have no value - " <>
          "declare default: <value>, make the attribute optional: true, or clear the rows" <>
          @reset_hint

      assert_error RuntimeError, expected_msg, fn ->
        reconcile(context)
      end
    end

    test "raises for a combined type change and tightening with NULLs despite a default" do
      reconcile(reconcile_context([Module2]))
      insert_module2_row("NULL", "'abc'")

      context =
        [Module2]
        |> reconcile_context()
        |> update_mapping_column(
          Module2,
          "b",
          &%{&1 | default: 4.2, sql_type: "float8", null: false}
        )

      expected_msg =
        ~s(cannot make column "b" on table "test_fixtures_entity_module2" required - ) <>
          "found 1 row with NULL - " <>
          "declare default: <value>, keep the attribute optional: true, or fix the data"

      assert_error RuntimeError, expected_msg, fn ->
        reconcile(context)
      end
    end

    test "renames an enum type standing under an old name, keeping its column's values" do
      context = reconcile_context([Module4])
      reconcile(context)
      insert_module4_row("y")

      enum_type = "test_fixtures_entity_module4_c_$enum"
      old_name = "test_fixtures_entity_module4_old_$enum"
      rename_enum_type_by_hand(enum_type, old_name)

      assert reconcile(context).ops == [
               %{op: :rename_enum_type, from: old_name, to: enum_type}
             ]

      assert Introspection.schema() == expected_schema(context)

      {:ok, %{rows: rows}} =
        Connection.query(~s(SELECT "c"::text FROM "hologram_data"."test_fixtures_entity_module4"))

      assert rows == [["y"]]

      assert {:enum_type, "", enum_type} in registry()
      refute {:enum_type, "", old_name} in registry()
    end

    test "refuses a renamed enum type losing a value rows still hold" do
      reconcile(reconcile_context([Module4]))
      insert_module4_row("y")

      rename_enum_type_by_hand(
        "test_fixtures_entity_module4_c_$enum",
        "test_fixtures_entity_module4_old_$enum"
      )

      context =
        [Module4]
        |> reconcile_context()
        |> update_mapping_column(Module4, "c", &%{&1 | enum_values: ["x"]})

      expected_msg =
        ~s(found 1 row in "test_fixtures_entity_module4"."c" ) <>
          "holding removed enum value 'y' - update the rows or re-add the value"

      assert_error RuntimeError, expected_msg, fn -> reconcile(context) end

      old_name = "test_fixtures_entity_module4_old_$enum"

      assert Map.has_key?(Introspection.schema().enum_types, old_name)
      assert {:enum_type, "", old_name} in registry()
    end

    test "renames an enum type under an old name and adds a value to it" do
      reconcile(reconcile_context([Module4]))
      insert_module4_row("y")

      enum_type = "test_fixtures_entity_module4_c_$enum"
      rename_enum_type_by_hand(enum_type, "test_fixtures_entity_module4_old_$enum")

      context =
        [Module4]
        |> reconcile_context()
        |> update_mapping_column(Module4, "c", &%{&1 | enum_values: ["x", "y", "z"]})

      reconcile(context)

      assert Introspection.schema() == expected_schema(context)
      assert Introspection.schema().enum_types[enum_type] == ["x", "y", "z"]

      {:ok, %{rows: rows}} =
        Connection.query(~s(SELECT "c"::text FROM "hologram_data"."test_fixtures_entity_module4"))

      assert rows == [["y"]]
    end

    test "renames an enum type under an old name and rebuilds it without a value no row holds" do
      reconcile(reconcile_context([Module4]))
      insert_module4_row("x")

      enum_type = "test_fixtures_entity_module4_c_$enum"
      rename_enum_type_by_hand(enum_type, "test_fixtures_entity_module4_old_$enum")

      context =
        [Module4]
        |> reconcile_context()
        |> update_mapping_column(Module4, "c", &%{&1 | enum_values: ["x"]})

      ExUnit.CaptureLog.capture_log(fn -> reconcile(context) end)

      assert Introspection.schema() == expected_schema(context)
      assert Introspection.schema().enum_types[enum_type] == ["x"]

      {:ok, %{rows: rows}} =
        Connection.query(~s(SELECT "c"::text FROM "hologram_data"."test_fixtures_entity_module4"))

      assert rows == [["x"]]
    end

    test "raises for an unregistered enum type the model's column matches" do
      context = reconcile_context([Module4])
      reconcile(context)

      enum_type = "test_fixtures_entity_module4_c_$enum"

      {:ok, _result} =
        Connection.query(
          ~s(ALTER TYPE "hologram_data".#{Mapper.quote_identifier(enum_type)} RENAME TO "hand_made_status")
        )

      {:ok, _result} =
        Connection.query(
          ~s(DELETE FROM "hologram_system"."schema_object" WHERE "kind" = 'enum_type' AND "name" = $1),
          [enum_type]
        )

      expected_msg =
        ~s(unknown enum type "hand_made_status" in the hologram_data schema - ) <>
          "this schema is model-managed - move the object to another schema or remove it"

      assert_error RuntimeError, expected_msg, fn -> reconcile(context) end
    end

    test "raises when removing an enum value that rows still hold" do
      reconcile(reconcile_context([Module4]))

      insert_statement = """
      INSERT INTO "hologram_data"."test_fixtures_entity_module4"
        ("id", "a", "b", "c", "d", "created_at", "server_created_at", "server_created_seq", "server_updated_at", "server_updated_seq", "updated_at", "$revisions")
      VALUES ('00000000-0000-0000-0000-000000000001', '2026-01-01', '2026-01-01 00:00:00+00',
              'y', 1.5, '2026-01-01 00:00:00+00', '2026-01-01 00:00:00+00', 0, '2026-01-01 00:00:00+00', 0, '2026-01-01 00:00:00+00', '{}')
      """

      {:ok, _result} = Connection.query(insert_statement)

      context =
        [Module4]
        |> reconcile_context()
        |> update_mapping_column(Module4, "c", &%{&1 | enum_values: ["x"]})

      expected_msg =
        ~s(found 1 row in "test_fixtures_entity_module4"."c" ) <>
          "holding removed enum value 'y' - update the rows or re-add the value"

      assert_error RuntimeError, expected_msg, fn ->
        reconcile(context)
      end
    end

    test "raises when adding a unique index over rows that repeat a value" do
      reconcile(reconcile_context([Module2]))
      insert_module2_rows(["abc", "abc"])

      context =
        [Module2]
        |> reconcile_context()
        |> update_mapping_indexes(Module2, fn indexes ->
          Map.put(indexes, "test_fixtures_entity_module2_c_$uidx", %{
            columns: ["c"],
            nulls_distinct: true,
            unique: true
          })
        end)

      expected_msg =
        ~s{found 1 duplicate key in "test_fixtures_entity_module2" over ("c") - } <>
          "a unique index cannot be built while rows repeat a key - " <>
          "update the rows or drop the unique declaration"

      assert_error RuntimeError, expected_msg, fn ->
        reconcile(context)
      end
    end

    test "raises when a key over a column added with a default meets rows repeating the rest" do
      reconcile(reconcile_context([Module2]))
      insert_module2_rows(["abc", "abc"])

      expected_msg =
        ~s{found 1 duplicate key in "test_fixtures_entity_module2" over ("c", "z") - } <>
          "a unique index cannot be built while rows repeat a key - " <>
          "update the rows or drop the unique declaration"

      assert_error RuntimeError, expected_msg, fn ->
        reconcile(key_over_added_column_context("en", false))
      end
    end

    test "builds a key over a column added with a default when no rows repeat the rest" do
      reconcile(reconcile_context([Module2]))
      insert_module2_rows(["abc", "abd"])

      context = key_over_added_column_context("en", false)
      reconcile(context)

      assert Introspection.schema() == expected_schema(context)
    end

    test "builds a key over a column added without a default over rows repeating the rest" do
      reconcile(reconcile_context([Module2]))
      insert_module2_rows(["abc", "abc"])

      context = key_over_added_column_context(nil, true)
      reconcile(context)

      assert Introspection.schema() == expected_schema(context)
    end

    # An optional column's default fills no existing row, so the rows hold NULL in it.
    test "builds a key over an optional column added with a default over rows repeating the rest" do
      reconcile(reconcile_context([Module2]))
      insert_module2_rows(["abc", "abc"])

      context = key_over_added_column_context("en", true)
      reconcile(context)

      assert Introspection.schema() == expected_schema(context)
    end

    test "raises when a key meets rows that repeat it once a tightened column is filled" do
      reconcile(reconcile_context([Module2]))
      insert_module2_rows(["abc", "abc"])

      context =
        [Module2]
        |> key_over_b_c_context()
        |> update_mapping_column(Module2, "b", &%{&1 | default: 7, null: false})

      assert_error RuntimeError, filled_duplicate_key_msg(), fn ->
        reconcile(context)
      end
    end

    test "raises when filling a tightened column makes rows repeat a key that stands" do
      reconcile(key_over_b_c_context([Module2]))
      insert_module2_rows(["abc", "abc"])

      context =
        [Module2]
        |> key_over_b_c_context()
        |> update_mapping_column(Module2, "b", &%{&1 | default: 7, null: false})

      assert_error RuntimeError, filled_duplicate_key_msg(), fn ->
        reconcile(context)
      end

      assert Introspection.schema() ==
               expected_schema(key_over_b_c_context([Module2]))
    end

    test "raises when a filled row would repeat the key of a row holding the default" do
      reconcile(key_over_b_c_context([Module2]))
      insert_module2_rows(["abc", "abc"])

      {:ok, _result} =
        Connection.query("""
        UPDATE "hologram_data"."test_fixtures_entity_module2" SET "b" = 7
        WHERE "id" = '00000000-0000-0000-0000-000000000001'
        """)

      context =
        [Module2]
        |> key_over_b_c_context()
        |> update_mapping_column(Module2, "b", &%{&1 | default: 7, null: false})

      assert_error RuntimeError, filled_duplicate_key_msg(), fn ->
        reconcile(context)
      end
    end

    # The fill touches no row here, so the refusal is the index build's.
    test "leaves rows that repeat a key without the fill to the index build" do
      reconcile(reconcile_context([Module2]))
      insert_module2_rows(["abc", "abd"])

      {:ok, _result} =
        Connection.query(~s(UPDATE "hologram_data"."test_fixtures_entity_module2" SET "b" = 5))

      context =
        "en"
        |> key_over_added_column_context(false)
        |> update_mapping_column(Module2, "b", &%{&1 | default: 7, null: false})
        |> update_mapping_indexes(Module2, fn indexes ->
          Map.put(indexes, "test_fixtures_entity_module2_b_z_$uidx", %{
            columns: ["b", "z"],
            nulls_distinct: true,
            unique: true
          })
        end)

      expected_msg =
        ~s{found 1 duplicate key in "test_fixtures_entity_module2" over ("b", "z") - } <>
          "a unique index cannot be built while rows repeat a key - " <>
          "update the rows or drop the unique declaration"

      assert_error RuntimeError, expected_msg, fn ->
        reconcile(context)
      end
    end

    test "fills a tightened column of a key that stands when no rows repeat the rest" do
      reconcile(key_over_b_c_context([Module2]))
      insert_module2_rows(["abc", "abd"])

      context =
        [Module2]
        |> key_over_b_c_context()
        |> update_mapping_column(Module2, "b", &%{&1 | default: 7, null: false})

      reconcile(context)

      assert Introspection.schema() == expected_schema(context)

      {:ok, %{rows: rows}} =
        Connection.query(
          ~s(SELECT "b" FROM "hologram_data"."test_fixtures_entity_module2" ORDER BY "id")
        )

      assert rows == [[7], [7]]
    end

    test "raises when making a to-one unique over rows that repeat a reference" do
      reconcile(non_unique_channel_context())

      {:ok, _result} =
        Connection.query("""
        INSERT INTO "hologram_data"."test_fixtures_entity_module26"
          ("id", "name", "name_$sort", "created_at", "server_created_at", "server_created_seq", "server_updated_at", "server_updated_seq", "updated_at", "$revisions")
        VALUES ('00000000-0000-0000-0000-000000000001', 'general', NULL,
                '2026-01-01 00:00:00+00', '2026-01-01 00:00:00+00', 0, '2026-01-01 00:00:00+00', 0, '2026-01-01 00:00:00+00', '{}')
        """)

      Enum.each(1..2, fn index ->
        {:ok, _result} =
          Connection.query("""
          INSERT INTO "hologram_data"."test_fixtures_entity_module27"
            ("id", "channel_id", "code", "summary", "summary_$sort", "created_at", "server_created_at", "server_created_seq", "server_updated_at", "server_updated_seq", "updated_at",
             "$revisions")
          VALUES ('00000000-0000-0000-0000-00000000001#{index}',
                  '00000000-0000-0000-0000-000000000001', NULL, 'welcome', NULL,
                  '2026-01-01 00:00:00+00', '2026-01-01 00:00:00+00', 0, '2026-01-01 00:00:00+00', 0, '2026-01-01 00:00:00+00', '{}')
          """)
      end)

      expected_msg =
        ~s{found 1 duplicate key in "test_fixtures_entity_module27" over ("channel_id") - } <>
          "a unique index cannot be built while rows repeat a key - " <>
          "update the rows or drop the unique declaration"

      assert_error RuntimeError, expected_msg, fn ->
        reconcile(reconcile_context([Module26, Module27]))
      end
    end
  end

  describe "reconcile/1 for the role grant store" do
    test "raises when removing a role that grants still hold" do
      user =
        %{email: "reconciler_1@example.com"}
        |> Module14.new()
        |> DB.create!()

      Auth.grant_role(user, Role.Module1)

      context =
        Reflection.list_entities()
        |> reconcile_context_with_grant_store()
        |> update_mapping_column(RoleGrant, "role", fn column ->
          %{column | enum_values: column.enum_values -- ["Hologram.Test.Fixtures.Role.Module1"]}
        end)

      expected_msg =
        ~s(found 1 row in "hologram_role_grant"."role" ) <>
          "holding removed enum value 'Hologram.Test.Fixtures.Role.Module1' - " <>
          "update the rows or re-add the value"

      assert_error RuntimeError, expected_msg, fn ->
        reconcile(context)
      end
    end
  end

  describe "registry/0" do
    test "returns an empty set when nothing is registered" do
      {:ok, _result} = Connection.query(~s(DELETE FROM "hologram_system"."schema_object"))

      assert registry() == MapSet.new()
    end
  end

  describe "system_schema_upgrades/0" do
    # What a later release's step has to follow, so a claimed database's version can never skip
    # a step or run one twice.
    test "numbers its steps one above the last, from 2" do
      steps = system_schema_upgrades()

      expected_versions =
        steps
        |> Enum.with_index(2)
        |> Enum.map(fn {_step, index} -> index end)

      assert Enum.map(steps, fn {version, _statements} -> version end) == expected_versions
    end
  end

  describe "system_schema_version/1" do
    test "is 1 without upgrade steps" do
      assert system_schema_version(%{system_upgrades: []}) == 1
    end

    test "is the last upgrade step's version" do
      assert system_schema_version(%{system_upgrades: [{2, []}, {3, []}]}) == 3
    end
  end

  describe "update_registry/1" do
    setup do
      {:ok, _result} = Connection.query(~s(DELETE FROM "hologram_system"."schema_object"))
      :ok
    end

    test "registers a created table with its columns and primary key constraint" do
      op = %{
        op: :create_table,
        table: "task",
        columns: %{
          "id" => %{type: "uuid", collation: nil, null: false},
          "name" => %{type: "text", collation: "C", null: false}
        },
        primary_key: %{columns: ["id"], constraint: "task_$pk"}
      }

      update_registry([op])

      assert registry() ==
               MapSet.new([
                 {:table, "", "task"},
                 {:column, "task", "id"},
                 {:column, "task", "name"},
                 {:constraint, "task", "task_$pk"}
               ])
    end

    test "registers added columns, foreign keys, indexes, and enum types" do
      ops = [
        %{
          op: :add_column,
          table: "task",
          column: "done",
          definition: %{type: "boolean", collation: nil, null: false}
        },
        %{
          op: :add_foreign_key,
          table: "task",
          column: "project_id",
          references: "project",
          on_delete: :restrict,
          constraint: "task_project_id_$fk"
        },
        %{
          op: :create_index,
          table: "task",
          index: "task_project_id_$idx",
          columns: ["project_id"]
        },
        %{op: :create_enum_type, enum_type: "task_status_$enum", values: ["todo"]}
      ]

      update_registry(ops)

      assert registry() ==
               MapSet.new([
                 {:column, "task", "done"},
                 {:constraint, "task", "task_project_id_$fk"},
                 {:index, "task", "task_project_id_$idx"},
                 {:enum_type, "", "task_status_$enum"}
               ])
    end

    test "deregisters a dropped table together with everything parented to it" do
      create_op = %{
        op: :create_table,
        table: "task",
        columns: %{"id" => %{type: "uuid", collation: nil, null: false}},
        primary_key: %{columns: ["id"], constraint: "task_$pk"}
      }

      other_op = %{op: :create_enum_type, enum_type: "task_status_$enum", values: ["todo"]}

      update_registry([create_op, other_op])
      update_registry([%{op: :drop_table, table: "task"}])

      assert registry() == MapSet.new([{:enum_type, "", "task_status_$enum"}])
    end

    test "deregisters dropped columns, foreign keys, indexes, and enum types" do
      add_ops = [
        %{
          op: :add_column,
          table: "task",
          column: "done",
          definition: %{type: "boolean", collation: nil, null: false}
        },
        %{
          op: :add_foreign_key,
          table: "task",
          column: "project_id",
          references: "project",
          on_delete: :restrict,
          constraint: "task_project_id_$fk"
        },
        %{
          op: :create_index,
          table: "task",
          index: "task_project_id_$idx",
          columns: ["project_id"]
        },
        %{op: :create_enum_type, enum_type: "task_status_$enum", values: ["todo"]}
      ]

      drop_ops = [
        %{op: :drop_column, table: "task", column: "done"},
        %{op: :drop_foreign_key, table: "task", constraint: "task_project_id_$fk"},
        %{op: :drop_index, index: "task_project_id_$idx"},
        %{op: :drop_enum_type, enum_type: "task_status_$enum"}
      ]

      update_registry(add_ops)
      update_registry(drop_ops)

      assert registry() == MapSet.new()
    end

    test "renames a registered constraint" do
      add_op = %{
        op: :add_foreign_key,
        table: "task",
        column: "project_id",
        references: "project",
        on_delete: :restrict,
        constraint: "task_project_id_fkey"
      }

      rename_op = %{
        op: :rename_constraint,
        table: "task",
        from: "task_project_id_fkey",
        to: "task_project_id_$fk"
      }

      update_registry([add_op])
      update_registry([rename_op])

      assert registry() == MapSet.new([{:constraint, "task", "task_project_id_$fk"}])
    end

    test "re-registering an existing object is a no-op" do
      op = %{
        op: :add_column,
        table: "task",
        column: "done",
        definition: %{type: "boolean", collation: nil, null: false}
      }

      update_registry([op])
      update_registry([op])

      assert registry() == MapSet.new([{:column, "task", "done"}])
    end

    test "leaves the registry untouched for identity-preserving ops" do
      ops = [
        %{
          op: :alter_column,
          table: "task",
          column: "done",
          before: %{type: "boolean", collation: nil, null: false},
          after: %{type: "boolean", collation: nil, null: true}
        },
        %{op: :add_enum_value, enum_type: "task_status_$enum", value: "done", position: nil},
        %{op: :rebuild_enum_type, enum_type: "task_status_$enum", values: ["todo"], columns: []},
        %{op: :rename_enum_value, enum_type: "task_status_$enum", from: "todo", to: "later"}
      ]

      update_registry(ops)

      assert registry() == MapSet.new()
    end
  end

  describe "upgrade_system_tables!/1" do
    setup do
      drop_hologram_schemas()
      ensure_managed!(Map.put(@context, :system_upgrades, []))
      :ok
    end

    test "runs the pending steps in order and returns their versions" do
      context = %{system_upgrades: [@create_probe_step, @alter_probe_step]}

      assert upgrade_system_tables!(context) == [2, 3]
      assert probe_columns() == ["id", "note"]
      assert read_marker().system_schema_version == 3
    end

    test "returns no versions for a database at the running layout" do
      set_system_schema_version(3)

      assert upgrade_system_tables!(%{system_upgrades: [@create_probe_step, @alter_probe_step]}) ==
               []

      assert probe_columns() == []
      assert read_marker().system_schema_version == 3
    end
  end

  describe "write_marker/1" do
    test "writes the given layout version" do
      write_marker(%{@marker | system_schema_version: 7})

      assert read_marker().system_schema_version == 7
    end

    test "replaces the previous marker row" do
      write_marker(@marker)
      write_marker(%{@marker | env: "dev", last_reconciled_at: ~U[2026-07-20 13:00:00.000000Z]})

      assert read_marker() == %{
               @marker
               | env: "dev",
                 last_reconciled_at: ~U[2026-07-20 13:00:00.000000Z]
             }
    end
  end
end
