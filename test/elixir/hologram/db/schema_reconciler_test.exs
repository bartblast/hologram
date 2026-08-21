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
  alias Hologram.DB.Introspection
  alias Hologram.DB.Mapper
  alias Hologram.DB.Schema
  alias Hologram.Entity
  alias Hologram.Reflection
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module4
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

  @not_managed_msg "the configured database contains Hologram schemas but no " <>
                     "managed-database marker - it is not managed by schema " <>
                     "reconciliation - drop the \"hologram_system\" and " <>
                     "\"hologram_data\" schemas or point the config at another database"

  defp drop_hologram_schemas do
    {:ok, _result} = Connection.query(~s(DROP SCHEMA "hologram_system" CASCADE))
    {:ok, _result} = Connection.query(~s(DROP SCHEMA "hologram_data" CASCADE))
  end

  defp insert_module2_row(b_value, c_value) do
    statement = """
    INSERT INTO "hologram_data"."test_fixtures_entity_module2"
      ("id", "a", "b", "c", "created_at", "updated_at")
    VALUES ('00000000-0000-0000-0000-000000000001', TRUE, #{b_value}, #{c_value},
            '2026-01-01 00:00:00+00', '2026-01-01 00:00:00+00')
    """

    {:ok, _result} = Connection.query(statement)
  end

  # The grant store is derived into every mapping - dropped here so a run converges
  # exactly the entity types the test names (its user references would otherwise point
  # at a table outside the mapping). Tests converging the store itself use
  # reconcile_context_with_grant_store/1.
  defp insert_module2_rows(c_values) do
    c_values
    |> Enum.with_index(1)
    |> Enum.each(fn {c_value, index} ->
      statement = """
      INSERT INTO "hologram_data"."test_fixtures_entity_module2"
        ("id", "a", "b", "c", "created_at", "updated_at")
      VALUES ('00000000-0000-0000-0000-00000000000#{index}', TRUE, NULL, '#{c_value}',
              '2026-01-01 00:00:00+00', '2026-01-01 00:00:00+00')
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

  defp reconcile_context(entity_types) do
    mapping =
      entity_types
      |> Mapper.derive!()
      |> Map.drop([RoleGrant])

    Map.put(@context, :mapping, mapping)
  end

  defp reconcile_context_with_grant_store(entity_types) do
    Map.put(@context, :mapping, Mapper.derive!(entity_types))
  end

  defp update_mapping_column(context, entity_type, column_name, fun) do
    update_in(context, [:mapping, entity_type, :columns], fn columns ->
      Enum.map(columns, fn
        %{name: ^column_name} = column -> fun.(column)
        column -> column
      end)
    end)
  end

  describe "backfill_sort_keys!/2" do
    setup do
      drop_hologram_schemas()
      reconcile(reconcile_context([Module2]))

      :ok
    end

    test "fills the companion an add-column op names" do
      insert_module2_rows(["Łódź"])
      {:ok, _result} = Connection.query(~s(UPDATE #{@module2_table} SET "c_$sort" = NULL))

      op = %{op: :add_column, table: "test_fixtures_entity_module2", column: "c_$sort"}

      assert backfill_sort_keys!([op], reconcile_context([Module2]).mapping) == :ok
      assert module2_sort_pairs() == [["Łódź", "lodz"]]
    end

    test "passes over an op adding a column that is no companion" do
      insert_module2_rows(["Łódź"])
      {:ok, _result} = Connection.query(~s(UPDATE #{@module2_table} SET "c_$sort" = NULL))

      op = %{op: :add_column, table: "test_fixtures_entity_module2", column: "c"}

      assert backfill_sort_keys!([op], reconcile_context([Module2]).mapping) == :ok
      assert module2_sort_pairs() == [["Łódź", nil]]
    end
  end

  describe "create_system_tables/0" do
    test "creates the marker, registry, migration, and outbox tables" do
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

      assert rows == [["database"], ["migration"], ["outbox"], ["schema_object"]]
    end

    test "gives the outbox the indexes reading it forward and pruning it behind need" do
      drop_hologram_schemas()
      {:ok, _result} = Connection.query(~s(CREATE SCHEMA "hologram_system"))

      assert create_system_tables() == :ok

      statement = """
      SELECT c.relname, am.amname, a.attname
      FROM pg_catalog.pg_class c
      JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
      JOIN pg_catalog.pg_am am ON am.oid = c.relam
      JOIN pg_catalog.pg_attribute a ON a.attrelid = c.oid
      WHERE n.nspname = 'hologram_system' AND c.relkind = 'i' AND c.relname LIKE 'outbox%'
      ORDER BY c.relname, a.attnum
      """

      {:ok, %{rows: rows}} = Connection.query(statement)

      # BRIN rather than btree for the prune scan: the table is append-only, so a btree here
      # would put its rightmost page in the path of every write to speed up an hourly chore.
      assert rows == [
               ["outbox_inserted_at_$idx", "brin", "inserted_at"],
               ["outbox_pkey", "btree", "seq"],
               ["outbox_tx_seq_$idx", "btree", "tx"],
               ["outbox_tx_seq_$idx", "btree", "seq"]
             ]
    end

    test "gives the outbox the columns the dispatcher and its writers need" do
      drop_hologram_schemas()
      {:ok, _result} = Connection.query(~s(CREATE SCHEMA "hologram_system"))

      assert create_system_tables() == :ok

      statement = """
      SELECT a.attname, format_type(a.atttypid, a.atttypmod), a.attnotnull
      FROM pg_catalog.pg_attribute a
      JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
      JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'hologram_system' AND c.relname = 'outbox' AND a.attnum > 0
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
               ["op", "text", true],
               ["seq", "bigint", true],
               ["tx", "xid8", true],
               ["type", "text", true]
             ]
    end

    # That two DIFFERENT transactions take different ids is not reachable here - the sandbox
    # runs every test inside one transaction, so these rows share it whatever the default does.
    # What this pins is that the default fires at all and that seq advances.
    test "stamps an outbox row with the transaction that wrote it" do
      drop_hologram_schemas()
      {:ok, _result} = Connection.query(~s(CREATE SCHEMA "hologram_system"))

      assert create_system_tables() == :ok

      insert = """
      INSERT INTO "hologram_system"."outbox" ("op", "type", "entity_id", "model_hash")
      VALUES ('put_entity', 'MyApp.Task', '00000000-0000-4000-8000-000000000001', 'abc123'),
             ('del_entity', 'MyApp.Task', '00000000-0000-4000-8000-000000000002', 'abc123')
      """

      {:ok, _result} = Connection.query(insert)

      {:ok, %{rows: [[writing_tx]]}} = Connection.query("SELECT pg_current_xact_id()")

      select = ~s(SELECT "seq", "tx" FROM "hologram_system"."outbox" ORDER BY "seq")
      {:ok, %{rows: [[first_seq, first_tx], [second_seq, second_tx]]}} = Connection.query(select)

      assert second_seq > first_seq
      assert first_tx == writing_tx
      assert second_tx == writing_tx
    end
  end

  describe "ensure_managed!/1" do
    test "claims a virgin database" do
      drop_hologram_schemas()

      assert ensure_managed!(@context) == :claimed

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

    test "returns :managed when the marker matches the context" do
      drop_hologram_schemas()
      ensure_managed!(@context)

      assert ensure_managed!(@context) == :managed
    end

    test "raises when Hologram schemas exist without a marker" do
      drop_hologram_schemas()
      {:ok, _result} = Connection.query(~s(CREATE SCHEMA "hologram_system"))
      {:ok, _result} = Connection.query(~s(CREATE SCHEMA "hologram_data"))

      assert_error RuntimeError, @not_managed_msg, fn ->
        ensure_managed!(@context)
      end
    end

    test "raises when only one Hologram schema exists" do
      drop_hologram_schemas()
      {:ok, _result} = Connection.query(~s(CREATE SCHEMA "hologram_data"))

      assert_error RuntimeError, @not_managed_msg, fn ->
        ensure_managed!(@context)
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
      assert Introspection.schema() == Schema.from_mapping(context.mapping)
      assert {:table, "", "test_fixtures_entity_module1"} in registry()
      assert read_marker().last_reconciled_at == @context.timestamp
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

      assert Introspection.schema() == Schema.from_mapping(context.mapping)
    end

    test "converges enum types" do
      context = reconcile_context([Module4])

      reconcile(context)

      assert Introspection.schema() == Schema.from_mapping(context.mapping)
    end

    test "converges additive model changes" do
      reconcile(reconcile_context([Module1]))
      context = reconcile_context([Module1, Module4])

      result = reconcile(context)

      assert result.status == :managed
      assert Introspection.schema() == Schema.from_mapping(context.mapping)
    end

    test "converges destructive model changes and cleans the registry" do
      reconcile(reconcile_context([Module1, Module4]))
      context = reconcile_context([Module1])

      reconcile(context)

      assert Introspection.schema() == Schema.from_mapping(context.mapping)
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

      assert Introspection.schema() == Schema.from_mapping(context.mapping)
    end

    test "converges an enum value removal when no rows hold it" do
      reconcile(reconcile_context([Module4]))

      context =
        [Module4]
        |> reconcile_context()
        |> update_mapping_column(Module4, "c", &%{&1 | enum_values: ["x"]})

      reconcile(context)

      assert Introspection.schema() == Schema.from_mapping(context.mapping)
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
      assert Introspection.schema() == Schema.from_mapping(context.mapping)
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
        index: nil,
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
      assert Introspection.schema() == Schema.from_mapping(context.mapping)
    end

    test "fills the sort-key companion of a column it adds" do
      reconcile(reconcile_context([Module2]))
      insert_module2_rows(["Zürich", "apple"])
      {:ok, _result} = Connection.query(~s(ALTER TABLE #{@module2_table} DROP COLUMN "c_$sort"))

      context = reconcile_context([Module2])

      reconcile(context)

      assert module2_sort_pairs() == [["apple", "apple"], ["Zürich", "zurich"]]
      assert Introspection.schema() == Schema.from_mapping(context.mapping)
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
        index: nil,
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

    test "raises when removing an enum value that rows still hold" do
      reconcile(reconcile_context([Module4]))

      insert_statement = """
      INSERT INTO "hologram_data"."test_fixtures_entity_module4"
        ("id", "a", "b", "c", "d", "created_at", "updated_at")
      VALUES ('00000000-0000-0000-0000-000000000001', '2026-01-01', '2026-01-01 00:00:00+00',
              'y', 1.5, '2026-01-01 00:00:00+00', '2026-01-01 00:00:00+00')
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
  end

  describe "reconcile/1 for the role grant store" do
    test "raises when removing a role that grants still hold" do
      user =
        Module14
        |> Entity.new(email: "reconciler_1@example.com")
        |> DB.create()

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

  describe "write_marker/1" do
    test "stamps the writer's system schema layout version over the given one" do
      write_marker(%{@marker | system_schema_version: 99})

      assert read_marker().system_schema_version == 1
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
