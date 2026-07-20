defmodule Hologram.Database.SchemaReconcilerTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.Database.SchemaReconciler

  alias Hologram.Database.Connection
  alias Hologram.Database.Introspection
  alias Hologram.Database.Mapper
  alias Hologram.Database.Schema
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module4

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
    last_reconciled_at: ~U[2026-07-20 12:30:00.000000Z]
  }

  @not_managed_msg "the configured database contains Hologram schemas but no " <>
                     "managed-database marker - it is not managed by schema " <>
                     "reconciliation - drop the \"hologram_system\" and " <>
                     "\"hologram_data\" schemas or point the config at another database"

  defp drop_hologram_schemas do
    {:ok, _result} = Connection.query(~s(DROP SCHEMA "hologram_system" CASCADE))
    {:ok, _result} = Connection.query(~s(DROP SCHEMA "hologram_data" CASCADE))
  end

  defp reconcile_context(entity_types) do
    Map.put(@context, :mapping, Mapper.derive!(entity_types))
  end

  describe "create_system_tables/0" do
    test "creates the marker and registry tables" do
      assert create_system_tables() == :ok

      assert read_marker() == nil
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
  end

  describe "read_marker/0" do
    test "returns nil when no marker has been written" do
      create_system_tables()

      assert read_marker() == nil
    end

    test "returns the written marker" do
      create_system_tables()
      write_marker(@marker)

      assert read_marker() == @marker
    end
  end

  describe "registry/0" do
    test "returns an empty set when nothing is registered" do
      create_system_tables()

      assert registry() == MapSet.new()
    end
  end

  describe "update_registry/1" do
    setup do
      create_system_tables()
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
    test "replaces the previous marker row" do
      create_system_tables()
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
