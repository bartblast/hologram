defmodule Hologram.Database.SchemaReconcilerTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.Database.SchemaReconciler

  @marker %{
    otp_app: "hologram",
    env: "test",
    managed_by: "reconciliation",
    hologram_version: "0.5.0",
    last_reconciled_at: ~U[2026-07-20 12:30:00.000000Z]
  }

  describe "create_system_tables/0" do
    test "creates the marker and registry tables" do
      assert create_system_tables() == :ok

      assert read_marker() == nil
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
