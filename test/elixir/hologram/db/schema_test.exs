defmodule Hologram.DB.SchemaTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.DB.Schema

  alias Hologram.DB.IndexPlan
  alias Hologram.DB.Mapper
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module19
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module4

  @task_table %{
    columns: %{
      "id" => %{type: "uuid", collation: nil, null: false},
      "name" => %{type: "text", collation: "C", null: false}
    },
    primary_key: %{columns: ["id"], constraint: "task_$pk"},
    foreign_keys: %{},
    indexes: %{}
  }

  @project_table %{
    columns: %{"id" => %{type: "uuid", collation: nil, null: false}},
    primary_key: %{columns: ["id"], constraint: "project_$pk"},
    foreign_keys: %{},
    indexes: %{}
  }

  # The grant store is derived into every mapping - dropped here so a projection test
  # sees exactly the entity types it names.
  defp app_mapping(entity_types) do
    entity_types
    |> Mapper.derive!([])
    |> Map.drop([Hologram.Auth.RoleGrant])
  end

  defp table(entity_type, table_name) do
    [entity_type]
    |> Mapper.derive!([])
    |> from_mapping()
    |> get_in([:tables, table_name])
  end

  describe "diff/2 - tables" do
    test "returns no ops for identical terms" do
      term = %{tables: %{"task" => @task_table}, enum_types: %{}}

      assert diff(term, term) == []
    end

    test "emits create_table with columns and primary key for target-only tables" do
      actual = %{tables: %{}, enum_types: %{}}
      target = %{tables: %{"task" => @task_table}, enum_types: %{}}

      assert diff(actual, target) == [
               %{
                 op: :create_table,
                 table: "task",
                 columns: @task_table.columns,
                 primary_key: @task_table.primary_key
               }
             ]
    end

    test "emits drop_table for actual-only tables" do
      actual = %{tables: %{"task" => @task_table}, enum_types: %{}}
      target = %{tables: %{}, enum_types: %{}}

      assert diff(actual, target) == [%{op: :drop_table, table: "task"}]
    end

    test "emits no table ops for tables present on both sides" do
      changed_task_table = %{
        @task_table
        | primary_key: %{columns: ["id"], constraint: "renamed_$pk"}
      }

      actual = %{tables: %{"task" => @task_table}, enum_types: %{}}
      target = %{tables: %{"task" => changed_task_table}, enum_types: %{}}

      table_ops =
        actual
        |> diff(target)
        |> Enum.filter(&(&1.op in [:create_table, :drop_table]))

      assert table_ops == []
    end

    test "orders ops alphabetically by table name within each kind" do
      actual = %{tables: %{"a_old" => @task_table, "b_old" => @project_table}, enum_types: %{}}

      target = %{
        tables: %{"a_new" => @task_table, "b_new" => @project_table},
        enum_types: %{}
      }

      ops =
        actual
        |> diff(target)
        |> Enum.map(&{&1.op, &1.table})

      assert ops == [
               {:drop_table, "a_old"},
               {:drop_table, "b_old"},
               {:create_table, "a_new"},
               {:create_table, "b_new"}
             ]
    end
  end

  describe "diff/2 - columns" do
    test "emits add_column with the definition for target-only columns" do
      target_task_table = %{
        @task_table
        | columns:
            Map.put(@task_table.columns, "done", %{type: "boolean", collation: nil, null: false})
      }

      actual = %{tables: %{"task" => @task_table}, enum_types: %{}}
      target = %{tables: %{"task" => target_task_table}, enum_types: %{}}

      assert diff(actual, target) == [
               %{
                 op: :add_column,
                 table: "task",
                 column: "done",
                 definition: %{type: "boolean", collation: nil, null: false}
               }
             ]
    end

    test "emits drop_column for actual-only columns" do
      target_task_table = %{@task_table | columns: Map.delete(@task_table.columns, "name")}

      actual = %{tables: %{"task" => @task_table}, enum_types: %{}}
      target = %{tables: %{"task" => target_task_table}, enum_types: %{}}

      assert diff(actual, target) == [%{op: :drop_column, table: "task", column: "name"}]
    end

    test "emits alter_column with before and after for changed definitions" do
      target_task_table = %{
        @task_table
        | columns:
            Map.put(@task_table.columns, "name", %{type: "text", collation: "C", null: true})
      }

      actual = %{tables: %{"task" => @task_table}, enum_types: %{}}
      target = %{tables: %{"task" => target_task_table}, enum_types: %{}}

      assert diff(actual, target) == [
               %{
                 op: :alter_column,
                 table: "task",
                 column: "name",
                 before: %{type: "text", collation: "C", null: false},
                 after: %{type: "text", collation: "C", null: true}
               }
             ]
    end

    test "emits no column ops for tables missing on either side" do
      actual = %{tables: %{"task" => @task_table}, enum_types: %{}}
      target = %{tables: %{"project" => @project_table}, enum_types: %{}}

      column_ops =
        actual
        |> diff(target)
        |> Enum.filter(&(&1.op in [:add_column, :drop_column, :alter_column]))

      assert column_ops == []
    end

    test "orders column ops by kind, then table and column name" do
      actual_project_table = %{
        @project_table
        | columns:
            Map.put(@project_table.columns, "old", %{type: "boolean", collation: nil, null: false})
      }

      target_task_table = %{
        @task_table
        | columns:
            @task_table.columns
            |> Map.delete("name")
            |> Map.put("done", %{type: "boolean", collation: nil, null: false})
      }

      target_project_table = %{
        @project_table
        | columns:
            Map.put(@project_table.columns, "id", %{type: "uuid", collation: nil, null: true})
      }

      actual = %{
        tables: %{"project" => actual_project_table, "task" => @task_table},
        enum_types: %{}
      }

      target = %{
        tables: %{"project" => target_project_table, "task" => target_task_table},
        enum_types: %{}
      }

      ops =
        actual
        |> diff(target)
        |> Enum.map(&{&1.op, &1.table, &1.column})

      assert ops == [
               {:drop_column, "project", "old"},
               {:drop_column, "task", "name"},
               {:add_column, "task", "done"},
               {:alter_column, "project", "id"}
             ]
    end
  end

  describe "diff/2 - constraints and indexes" do
    @task_fk %{references: "project", on_delete: :restrict, constraint: "task_project_id_$fk"}

    defp with_foreign_key(table_definition, column, fk) do
      %{table_definition | foreign_keys: Map.put(table_definition.foreign_keys, column, fk)}
    end

    defp with_index(table_definition, name, columns, unique \\ false) do
      index = %{columns: columns, nulls_distinct: true, unique: unique}

      %{table_definition | indexes: Map.put(table_definition.indexes, name, index)}
    end

    test "emits add_foreign_key for target-only foreign keys" do
      actual = %{tables: %{"task" => @task_table}, enum_types: %{}}

      target = %{
        tables: %{"task" => with_foreign_key(@task_table, "project_id", @task_fk)},
        enum_types: %{}
      }

      assert diff(actual, target) == [
               %{
                 op: :add_foreign_key,
                 table: "task",
                 column: "project_id",
                 references: "project",
                 on_delete: :restrict,
                 constraint: "task_project_id_$fk"
               }
             ]
    end

    test "emits drop_foreign_key for actual-only foreign keys" do
      actual = %{
        tables: %{"task" => with_foreign_key(@task_table, "project_id", @task_fk)},
        enum_types: %{}
      }

      target = %{tables: %{"task" => @task_table}, enum_types: %{}}

      assert diff(actual, target) == [
               %{op: :drop_foreign_key, table: "task", constraint: "task_project_id_$fk"}
             ]
    end

    test "emits drop plus add for a structural foreign key change" do
      changed_fk = %{@task_fk | references: "workspace"}

      actual = %{
        tables: %{"task" => with_foreign_key(@task_table, "project_id", @task_fk)},
        enum_types: %{}
      }

      target = %{
        tables: %{"task" => with_foreign_key(@task_table, "project_id", changed_fk)},
        enum_types: %{}
      }

      assert diff(actual, target) == [
               %{op: :drop_foreign_key, table: "task", constraint: "task_project_id_$fk"},
               %{
                 op: :add_foreign_key,
                 table: "task",
                 column: "project_id",
                 references: "workspace",
                 on_delete: :restrict,
                 constraint: "task_project_id_$fk"
               }
             ]
    end

    test "emits rename_constraint for a foreign key name-only mismatch" do
      legacy_fk = %{@task_fk | constraint: "task_project_id_fkey"}

      actual = %{
        tables: %{"task" => with_foreign_key(@task_table, "project_id", legacy_fk)},
        enum_types: %{}
      }

      target = %{
        tables: %{"task" => with_foreign_key(@task_table, "project_id", @task_fk)},
        enum_types: %{}
      }

      assert diff(actual, target) == [
               %{
                 op: :rename_constraint,
                 table: "task",
                 from: "task_project_id_fkey",
                 to: "task_project_id_$fk"
               }
             ]
    end

    test "emits rename_constraint for a primary key name-only mismatch" do
      legacy_task_table = %{
        @task_table
        | primary_key: %{columns: ["id"], constraint: "task_pkey"}
      }

      actual = %{tables: %{"task" => legacy_task_table}, enum_types: %{}}
      target = %{tables: %{"task" => @task_table}, enum_types: %{}}

      assert diff(actual, target) == [
               %{op: :rename_constraint, table: "task", from: "task_pkey", to: "task_$pk"}
             ]
    end

    test "raises on primary key columns mismatch" do
      edited_task_table = %{
        @task_table
        | primary_key: %{columns: ["id", "name"], constraint: "task_$pk"}
      }

      actual = %{tables: %{"task" => edited_task_table}, enum_types: %{}}
      target = %{tables: %{"task" => @task_table}, enum_types: %{}}

      expected_msg =
        ~s(primary key columns mismatch on table "task" ) <>
          ~s{(actual: ["id", "name"], target: ["id"]) - } <>
          "no derivable schema can produce this, the database was edited by hand"

      assert_error RuntimeError, expected_msg, fn ->
        diff(actual, target)
      end
    end

    test "emits create_index for target-only indexes" do
      actual = %{tables: %{"task" => @task_table}, enum_types: %{}}

      target = %{
        tables: %{"task" => with_index(@task_table, "task_project_id_$idx", ["project_id"])},
        enum_types: %{}
      }

      assert diff(actual, target) == [
               %{
                 op: :create_index,
                 table: "task",
                 index: "task_project_id_$idx",
                 columns: ["project_id"],
                 nulls_distinct: true,
                 unique: false
               }
             ]
    end

    test "emits drop_index for actual-only indexes" do
      actual = %{
        tables: %{"task" => with_index(@task_table, "task_project_id_$idx", ["project_id"])},
        enum_types: %{}
      }

      target = %{tables: %{"task" => @task_table}, enum_types: %{}}

      assert diff(actual, target) == [%{op: :drop_index, index: "task_project_id_$idx"}]
    end

    test "emits drop plus create for an index definition change" do
      actual = %{
        tables: %{"task" => with_index(@task_table, "task_project_id_$idx", ["project_id"])},
        enum_types: %{}
      }

      target = %{
        tables: %{
          "task" => with_index(@task_table, "task_project_id_$idx", ["project_id", "name"])
        },
        enum_types: %{}
      }

      assert diff(actual, target) == [
               %{op: :drop_index, index: "task_project_id_$idx"},
               %{
                 op: :create_index,
                 table: "task",
                 index: "task_project_id_$idx",
                 columns: ["project_id", "name"],
                 nulls_distinct: true,
                 unique: false
               }
             ]
    end

    test "emits create_index carrying unique for a target-only unique index" do
      actual = %{tables: %{"task" => @task_table}, enum_types: %{}}

      target = %{
        tables: %{"task" => with_index(@task_table, "task_name_$uidx", ["name"], true)},
        enum_types: %{}
      }

      assert diff(actual, target) == [
               %{
                 op: :create_index,
                 table: "task",
                 index: "task_name_$uidx",
                 columns: ["name"],
                 nulls_distinct: true,
                 unique: true
               }
             ]
    end

    test "emits drop_index for an actual-only unique index" do
      actual = %{
        tables: %{"task" => with_index(@task_table, "task_name_$uidx", ["name"], true)},
        enum_types: %{}
      }

      target = %{tables: %{"task" => @task_table}, enum_types: %{}}

      assert diff(actual, target) == [%{op: :drop_index, index: "task_name_$uidx"}]
    end

    test "emits foreign key and index adds for new tables" do
      new_table =
        @task_table
        |> with_foreign_key("project_id", @task_fk)
        |> with_index("task_project_id_$idx", ["project_id"])

      actual = %{tables: %{}, enum_types: %{}}
      target = %{tables: %{"task" => new_table}, enum_types: %{}}

      op_kinds =
        actual
        |> diff(target)
        |> Enum.map(& &1.op)

      assert op_kinds == [:create_table, :add_foreign_key, :create_index]
    end

    test "emits the foreign key drops but no index drops for dropped tables" do
      dropped_table =
        @task_table
        |> with_foreign_key("project_id", @task_fk)
        |> with_index("task_project_id_$idx", ["project_id"])

      actual = %{tables: %{"task" => dropped_table}, enum_types: %{}}
      target = %{tables: %{}, enum_types: %{}}

      assert diff(actual, target) == [
               %{op: :drop_foreign_key, table: "task", constraint: "task_project_id_$fk"},
               %{op: :drop_table, table: "task"}
             ]
    end

    test "drops the foreign keys of both tables before dropping either one" do
      # The referenced table sorts first, so it is dropped first - which PostgreSQL refuses
      # while the other table's constraint still references it. Every constraint has to be
      # gone before the first table drop, whatever the names are.
      referencing_table = with_foreign_key(@task_table, "project_id", @task_fk)

      actual = %{
        tables: %{"project" => @project_table, "task" => referencing_table},
        enum_types: %{}
      }

      target = %{tables: %{}, enum_types: %{}}

      assert diff(actual, target) == [
               %{op: :drop_foreign_key, table: "task", constraint: "task_project_id_$fk"},
               %{op: :drop_table, table: "project"},
               %{op: :drop_table, table: "task"}
             ]
    end
  end

  describe "diff/2 - enum types" do
    test "returns no ops for identical enum types" do
      term = %{tables: %{}, enum_types: %{"task_status_$enum" => ["todo", "done"]}}

      assert diff(term, term) == []
    end

    test "emits create_enum_type with values for target-only types" do
      actual = %{tables: %{}, enum_types: %{}}
      target = %{tables: %{}, enum_types: %{"task_status_$enum" => ["todo", "done"]}}

      assert diff(actual, target) == [
               %{
                 op: :create_enum_type,
                 enum_type: "task_status_$enum",
                 values: ["todo", "done"]
               }
             ]
    end

    test "emits drop_enum_type for actual-only types" do
      actual = %{tables: %{}, enum_types: %{"task_status_$enum" => ["todo", "done"]}}
      target = %{tables: %{}, enum_types: %{}}

      assert diff(actual, target) == [%{op: :drop_enum_type, enum_type: "task_status_$enum"}]
    end

    test "emits add_enum_value with nil position for values appended at the tail" do
      actual = %{tables: %{}, enum_types: %{"task_status_$enum" => ["todo", "done"]}}

      target = %{
        tables: %{},
        enum_types: %{"task_status_$enum" => ["todo", "done", "archived"]}
      }

      assert diff(actual, target) == [
               %{
                 op: :add_enum_value,
                 enum_type: "task_status_$enum",
                 value: "archived",
                 position: nil
               }
             ]
    end

    test "emits add_enum_value anchored before the nearest following pre-existing value" do
      actual = %{tables: %{}, enum_types: %{"task_status_$enum" => ["todo", "done"]}}

      target = %{
        tables: %{},
        enum_types: %{"task_status_$enum" => ["draft", "todo", "doing", "review", "done"]}
      }

      assert diff(actual, target) == [
               %{
                 op: :add_enum_value,
                 enum_type: "task_status_$enum",
                 value: "draft",
                 position: {:before, "todo"}
               },
               %{
                 op: :add_enum_value,
                 enum_type: "task_status_$enum",
                 value: "doing",
                 position: {:before, "done"}
               },
               %{
                 op: :add_enum_value,
                 enum_type: "task_status_$enum",
                 value: "review",
                 position: {:before, "done"}
               }
             ]
    end

    test "emits rebuild_enum_type for value removal" do
      actual = %{tables: %{}, enum_types: %{"task_status_$enum" => ["todo", "doing", "done"]}}
      target = %{tables: %{}, enum_types: %{"task_status_$enum" => ["todo", "done"]}}

      assert diff(actual, target) == [
               %{
                 op: :rebuild_enum_type,
                 enum_type: "task_status_$enum",
                 values: ["todo", "done"],
                 columns: []
               }
             ]
    end

    test "emits rebuild_enum_type for value reorder" do
      actual = %{tables: %{}, enum_types: %{"task_status_$enum" => ["todo", "done"]}}
      target = %{tables: %{}, enum_types: %{"task_status_$enum" => ["done", "todo"]}}

      assert diff(actual, target) == [
               %{
                 op: :rebuild_enum_type,
                 enum_type: "task_status_$enum",
                 values: ["done", "todo"],
                 columns: []
               }
             ]
    end

    test "rebuild_enum_type carries the columns using the type" do
      status_column = %{type: "task_status_$enum", collation: nil, null: false}

      task_table = %{
        @task_table
        | columns: Map.put(@task_table.columns, "status", status_column)
      }

      project_table = %{
        @project_table
        | columns: Map.put(@project_table.columns, "state", status_column)
      }

      tables = %{"project" => project_table, "task" => task_table}

      actual = %{tables: tables, enum_types: %{"task_status_$enum" => ["todo", "done"]}}
      target = %{tables: tables, enum_types: %{"task_status_$enum" => ["done"]}}

      assert diff(actual, target) == [
               %{
                 op: :rebuild_enum_type,
                 enum_type: "task_status_$enum",
                 values: ["done"],
                 columns: [{"project", "state"}, {"task", "status"}]
               }
             ]
    end
  end

  describe "diff/2 - phase ordering" do
    test "orders ops across all kinds by the apply-phase sequence" do
      actual_task_table =
        @task_table
        |> Map.put(:primary_key, %{columns: ["id"], constraint: "task_pkey"})
        |> Map.update!(
          :columns,
          &Map.put(&1, "legacy", %{type: "boolean", collation: nil, null: false})
        )
        |> Map.put(:foreign_keys, %{
          "project_id" => %{
            references: "project",
            on_delete: :restrict,
            constraint: "task_project_id_$fk"
          }
        })
        |> Map.put(:indexes, %{
          "task_old_$idx" => %{columns: ["legacy"], nulls_distinct: true, unique: false},
          "task_renamed_from_$idx" => %{columns: ["id"], nulls_distinct: true, unique: false}
        })

      target_task_table =
        @task_table
        |> Map.update!(:columns, fn columns ->
          columns
          |> Map.put("done", %{type: "boolean", collation: nil, null: false})
          |> Map.put("name", %{type: "text", collation: "C", null: true})
        end)
        |> Map.put(:foreign_keys, %{
          "project_id" => %{
            references: "workspace",
            on_delete: :restrict,
            constraint: "task_project_id_$fk"
          }
        })
        |> Map.put(:indexes, %{
          "task_new_$idx" => %{columns: ["done"], nulls_distinct: true, unique: false},
          "task_renamed_to_$idx" => %{columns: ["id"], nulls_distinct: true, unique: false}
        })

      actual = %{
        tables: %{"old" => @project_table, "task" => actual_task_table},
        enum_types: %{
          "old_$enum" => ["x"],
          "status_$enum" => ["todo"]
        }
      }

      target = %{
        tables: %{"fresh" => @project_table, "task" => target_task_table},
        enum_types: %{
          "new_$enum" => ["a"],
          "status_$enum" => ["todo", "done"]
        }
      }

      op_kinds =
        actual
        |> diff(target)
        |> Enum.map(& &1.op)

      assert op_kinds == [
               :rename_index,
               :drop_foreign_key,
               :drop_index,
               :drop_column,
               :drop_table,
               :drop_enum_type,
               :create_enum_type,
               :add_enum_value,
               :create_table,
               :add_column,
               :alter_column,
               :rename_constraint,
               :add_foreign_key,
               :create_index
             ]
    end
  end

  describe "diff/2 - renames" do
    @project_id_index %{columns: ["project_id"], nulls_distinct: true, unique: false}

    defp with_indexes(table_definition, indexes) do
      %{table_definition | indexes: indexes}
    end

    defp task_term(indexes, tables \\ %{}) do
      %{tables: Map.put(tables, "task", with_indexes(@task_table, indexes)), enum_types: %{}}
    end

    defp join_table_term(name, source_table, target_table) do
      uuid_column = %{type: "uuid", collation: nil, null: false}

      %{
        columns: %{"source_id" => uuid_column, "target_id" => uuid_column},
        primary_key: %{columns: ["source_id", "target_id"], constraint: "#{name}_$pk"},
        foreign_keys: %{
          "source_id" => %{
            references: source_table,
            on_delete: :restrict,
            constraint: "#{name}_source_id_$fk"
          },
          "target_id" => %{
            references: target_table,
            on_delete: :restrict,
            constraint: "#{name}_target_id_$fk"
          }
        },
        indexes: %{
          "#{name}_target_id_source_id_$idx" => %{
            columns: ["target_id", "source_id"],
            nulls_distinct: true,
            unique: false
          }
        }
      }
    end

    defp join_term(join_tables) do
      tables =
        Map.new(join_tables, fn {name, source_table, target_table} ->
          {name, join_table_term(name, source_table, target_table)}
        end)

      %{
        tables: Map.merge(%{"task" => @task_table, "project" => @project_table}, tables),
        enum_types: %{}
      }
    end

    test "renames a join table with the same ends, along with its constraints and reverse index" do
      actual = join_term([{"task_tags_$join", "task", "project"}])
      target = join_term([{"task_labels_$join", "task", "project"}])

      assert diff(actual, target) == [
               %{op: :rename_table, from: "task_tags_$join", to: "task_labels_$join"},
               %{
                 op: :rename_index,
                 table: "task_labels_$join",
                 from: "task_tags_$join_target_id_source_id_$idx",
                 to: "task_labels_$join_target_id_source_id_$idx"
               },
               %{
                 op: :rename_constraint,
                 table: "task_labels_$join",
                 from: "task_tags_$join_$pk",
                 to: "task_labels_$join_$pk"
               },
               %{
                 op: :rename_constraint,
                 table: "task_labels_$join",
                 from: "task_tags_$join_source_id_$fk",
                 to: "task_labels_$join_source_id_$fk"
               },
               %{
                 op: :rename_constraint,
                 table: "task_labels_$join",
                 from: "task_tags_$join_target_id_$fk",
                 to: "task_labels_$join_target_id_$fk"
               }
             ]
    end

    test "pairs no join table when two on one side share the ends" do
      actual =
        join_term([
          {"task_tags_$join", "task", "project"},
          {"task_blocked_$join", "task", "project"}
        ])

      target = join_term([{"task_labels_$join", "task", "project"}])

      op_kinds =
        actual
        |> diff(target)
        |> Enum.map(& &1.op)

      refute :rename_table in op_kinds
      assert Enum.count(op_kinds, &(&1 == :drop_table)) == 2
      assert :create_table in op_kinds
    end

    test "pairs a join table beside another with the same ends that both sides keep" do
      actual =
        join_term([
          {"task_tags_$join", "task", "project"},
          {"task_kept_$join", "task", "project"}
        ])

      target =
        join_term([
          {"task_labels_$join", "task", "project"},
          {"task_kept_$join", "task", "project"}
        ])

      assert [%{op: :rename_table, from: "task_tags_$join", to: "task_labels_$join"} | _ops] =
               diff(actual, target)
    end

    test "pairs no join table when two on the target side share the ends" do
      actual = join_term([{"task_tags_$join", "task", "project"}])

      target =
        join_term([
          {"task_labels_$join", "task", "project"},
          {"task_blocked_$join", "task", "project"}
        ])

      op_kinds =
        actual
        |> diff(target)
        |> Enum.map(& &1.op)

      refute :rename_table in op_kinds
      assert Enum.count(op_kinds, &(&1 == :create_table)) == 2
    end

    test "renames a self-referential join table" do
      actual = join_term([{"task_parents_$join", "task", "task"}])
      target = join_term([{"task_children_$join", "task", "task"}])

      assert [%{op: :rename_table, from: "task_parents_$join", to: "task_children_$join"} | _ops] =
               diff(actual, target)
    end

    test "pairs no join-shaped table a hand edit left without a foreign key" do
      actual =
        update_in(
          join_term([{"task_tags_$join", "task", "project"}]).tables["task_tags_$join"].foreign_keys,
          &Map.delete(&1, "target_id")
        )

      target = join_term([{"task_labels_$join", "task", "project"}])

      op_kinds =
        actual
        |> diff(target)
        |> Enum.map(& &1.op)

      refute :rename_table in op_kinds
    end

    test "pairs no join-shaped table holding a third column" do
      extra_column = %{type: "text", collation: "C", null: true}

      actual =
        update_in(
          join_term([{"task_tags_$join", "task", "project"}]).tables["task_tags_$join"].columns,
          &Map.put(&1, "note", extra_column)
        )

      target = join_term([{"task_labels_$join", "task", "project"}])

      op_kinds =
        actual
        |> diff(target)
        |> Enum.map(& &1.op)

      refute :rename_table in op_kinds
    end

    test "orders a join table rename before every drop" do
      actual =
        join_term([
          {"task_tags_$join", "task", "project"},
          {"task_gone_$join", "project", "task"}
        ])

      target = join_term([{"task_labels_$join", "task", "project"}])

      op_kinds =
        actual
        |> diff(target)
        |> Enum.map(& &1.op)

      assert [:rename_table, :rename_index, :drop_foreign_key | _later] = op_kinds
      assert :drop_table in op_kinds
    end

    test "keeps join tables a drop plus a create with renames: false" do
      actual = join_term([{"task_tags_$join", "task", "project"}])
      target = join_term([{"task_labels_$join", "task", "project"}])

      op_kinds =
        actual
        |> diff(target, renames: false)
        |> Enum.map(& &1.op)

      refute :rename_table in op_kinds
      assert :drop_table in op_kinds
      assert :create_table in op_kinds
    end

    test "pairs no join table whose ends differ" do
      actual = join_term([{"task_tags_$join", "task", "project"}])
      target = join_term([{"task_labels_$join", "project", "task"}])

      op_kinds =
        actual
        |> diff(target)
        |> Enum.map(& &1.op)

      refute :rename_table in op_kinds
      assert :drop_table in op_kinds
      assert :create_table in op_kinds
    end

    test "pairs no join-shaped table a hand edit left without its primary key" do
      actual =
        put_in(
          join_term([{"task_tags_$join", "task", "project"}]).tables["task_tags_$join"].primary_key,
          nil
        )

      target = join_term([{"task_labels_$join", "task", "project"}])

      op_kinds =
        actual
        |> diff(target)
        |> Enum.map(& &1.op)

      refute :rename_table in op_kinds
      assert :drop_table in op_kinds
    end

    test "pairs no entity table" do
      actual = %{tables: %{"task" => @task_table}, enum_types: %{}}
      target = %{tables: %{"todo" => @task_table}, enum_types: %{}}

      op_kinds =
        actual
        |> diff(target)
        |> Enum.map(& &1.op)

      assert op_kinds == [:drop_table, :create_table]
    end

    defp status_term(enum_type, values) do
      status_column = %{type: enum_type, collation: nil, null: false}
      table = %{@task_table | columns: Map.put(@task_table.columns, "status", status_column)}

      %{tables: %{"task" => table}, enum_types: %{enum_type => values}}
    end

    test "emits a lone rename_enum_type for a type renamed under the column using it" do
      actual = status_term("task_old_$enum", ["todo", "done"])
      target = status_term("task_status_$enum", ["todo", "done"])

      assert diff(actual, target) == [
               %{op: :rename_enum_type, from: "task_old_$enum", to: "task_status_$enum"}
             ]
    end

    test "adds a value to a renamed enum type under its new name" do
      actual = status_term("task_old_$enum", ["todo"])
      target = status_term("task_status_$enum", ["todo", "done"])

      assert diff(actual, target) == [
               %{op: :rename_enum_type, from: "task_old_$enum", to: "task_status_$enum"},
               %{
                 op: :add_enum_value,
                 enum_type: "task_status_$enum",
                 value: "done",
                 position: nil
               }
             ]
    end

    test "rebuilds a renamed enum type losing a value under its new name" do
      actual = status_term("task_old_$enum", ["todo", "done"])
      target = status_term("task_status_$enum", ["todo"])

      assert diff(actual, target) == [
               %{op: :rename_enum_type, from: "task_old_$enum", to: "task_status_$enum"},
               %{
                 op: :rebuild_enum_type,
                 enum_type: "task_status_$enum",
                 values: ["todo"],
                 columns: [{"task", "status"}]
               }
             ]
    end

    test "pairs no enum type a second column ties to another type" do
      phase_column = fn enum_type -> %{type: enum_type, collation: nil, null: false} end

      actual =
        put_in(
          status_term("task_old_$enum", ["todo"]).tables["task"].columns["phase"],
          phase_column.("task_old_$enum")
        )

      target =
        "task_status_$enum"
        |> status_term(["todo"])
        |> put_in([:tables, "task", :columns, "phase"], phase_column.("task_phase_$enum"))
        |> put_in([:enum_types, "task_phase_$enum"], ["todo"])

      op_kinds =
        actual
        |> diff(target)
        |> Enum.map(& &1.op)

      refute :rename_enum_type in op_kinds
    end

    test "pairs no enum type another of its columns leaves for text" do
      text_column = %{type: "text", collation: "C", null: false}

      actual =
        put_in(
          status_term("task_old_$enum", ["todo"]).tables["task"].columns["phase"],
          %{type: "task_old_$enum", collation: nil, null: false}
        )

      target =
        put_in(
          status_term("task_status_$enum", ["todo"]).tables["task"].columns["phase"],
          text_column
        )

      op_kinds =
        actual
        |> diff(target)
        |> Enum.map(& &1.op)

      refute :rename_enum_type in op_kinds
    end

    test "renames one enum type for every column that moves with it" do
      enum_column = fn enum_type -> %{type: enum_type, collation: nil, null: false} end

      actual =
        put_in(
          status_term("task_old_$enum", ["todo", "done"]).tables["task"].columns["phase"],
          enum_column.("task_old_$enum")
        )

      target =
        put_in(
          status_term("task_status_$enum", ["todo"]).tables["task"].columns["phase"],
          enum_column.("task_status_$enum")
        )

      assert diff(actual, target) == [
               %{op: :rename_enum_type, from: "task_old_$enum", to: "task_status_$enum"},
               %{
                 op: :rebuild_enum_type,
                 enum_type: "task_status_$enum",
                 values: ["todo"],
                 columns: [{"task", "phase"}, {"task", "status"}]
               }
             ]
    end

    test "keeps enum types a drop plus a create with renames: false" do
      actual = status_term("task_old_$enum", ["todo"])
      target = status_term("task_status_$enum", ["todo"])

      op_kinds =
        actual
        |> diff(target, renames: false)
        |> Enum.map(& &1.op)

      assert op_kinds == [:drop_enum_type, :create_enum_type, :alter_column]
    end

    test "emits a lone rename_index for an index whose name changed and definition didn't" do
      actual = task_term(%{"task_old_$idx" => @project_id_index})
      target = task_term(%{"task_new_$idx" => @project_id_index})

      assert diff(actual, target) == [
               %{op: :rename_index, table: "task", from: "task_old_$idx", to: "task_new_$idx"}
             ]
    end

    test "emits drop plus create for an index whose definition changed with its name" do
      actual = task_term(%{"task_old_$idx" => @project_id_index})
      target = task_term(%{"task_new_$idx" => %{@project_id_index | unique: true}})

      assert diff(actual, target) == [
               %{op: :drop_index, index: "task_old_$idx"},
               %{
                 op: :create_index,
                 table: "task",
                 index: "task_new_$idx",
                 columns: ["project_id"],
                 nulls_distinct: true,
                 unique: true
               }
             ]
    end

    test "pairs nothing when two unmatched indexes share the definition" do
      actual =
        task_term(%{"task_a_$idx" => @project_id_index, "task_b_$idx" => @project_id_index})

      target = task_term(%{"task_new_$idx" => @project_id_index})

      op_kinds =
        actual
        |> diff(target)
        |> Enum.map(& &1.op)

      assert op_kinds == [:drop_index, :drop_index, :create_index]
    end

    test "pairs nothing when two unmatched target indexes share the definition" do
      actual = task_term(%{"task_old_$idx" => @project_id_index})

      target =
        task_term(%{"task_a_$idx" => @project_id_index, "task_b_$idx" => @project_id_index})

      op_kinds =
        actual
        |> diff(target)
        |> Enum.map(& &1.op)

      assert op_kinds == [:drop_index, :create_index, :create_index]
    end

    test "pairs only the first of two renames to one name on different tables" do
      project_table = with_indexes(@project_table, %{"project_old_$idx" => @project_id_index})

      actual = task_term(%{"task_old_$idx" => @project_id_index}, %{"project" => project_table})

      target =
        task_term(%{"shared_$idx" => @project_id_index}, %{
          "project" => with_indexes(@project_table, %{"shared_$idx" => @project_id_index})
        })

      assert [
               %{op: :rename_index, table: "project", from: "project_old_$idx", to: "shared_$idx"}
               | other_ops
             ] = diff(actual, target)

      refute Enum.any?(other_ops, &(&1.op == :rename_index))
    end

    test "pairs an index on a table with no primary key" do
      actual =
        put_in(task_term(%{"task_old_$idx" => @project_id_index}).tables["task"].primary_key, nil)

      target = task_term(%{"task_new_$idx" => @project_id_index})

      assert [%{op: :rename_index, from: "task_old_$idx", to: "task_new_$idx"} | _other_ops] =
               diff(actual, target)
    end

    test "pairs nothing when another actual index holds the target name" do
      other_table = with_indexes(@project_table, %{"task_new_$idx" => @project_id_index})

      actual = task_term(%{"task_old_$idx" => @project_id_index}, %{"project" => other_table})
      target = task_term(%{"task_new_$idx" => @project_id_index}, %{"project" => @project_table})

      op_kinds =
        actual
        |> diff(target)
        |> Enum.map(& &1.op)

      assert op_kinds == [:drop_index, :drop_index, :create_index]
    end

    test "pairs nothing when a primary key holds the target name" do
      actual = task_term(%{"task_old_$idx" => @project_id_index})
      target = task_term(%{"task_$pk" => @project_id_index})

      op_kinds =
        actual
        |> diff(target)
        |> Enum.map(& &1.op)

      assert op_kinds == [:drop_index, :create_index]
    end

    test "orders the renames before every drop" do
      legacy_column = %{type: "boolean", collation: nil, null: false}

      actual_table =
        @task_table
        |> with_indexes(%{"task_old_$idx" => @project_id_index})
        |> Map.update!(:columns, &Map.put(&1, "legacy", legacy_column))

      actual = %{tables: %{"task" => actual_table}, enum_types: %{}}
      target = task_term(%{"task_new_$idx" => @project_id_index})

      assert diff(actual, target) == [
               %{op: :rename_index, table: "task", from: "task_old_$idx", to: "task_new_$idx"},
               %{op: :drop_column, table: "task", column: "legacy"}
             ]
    end

    test "pairs no index introspection marked as not plain" do
      partial_index = Map.put(@project_id_index, :non_plain, [:predicate])

      actual = task_term(%{"task_old_$idx" => partial_index})
      target = task_term(%{"task_new_$idx" => @project_id_index})

      op_kinds =
        actual
        |> diff(target)
        |> Enum.map(& &1.op)

      assert op_kinds == [:drop_index, :create_index]
    end

    test "drops and recreates a marked index under the target's name, carrying its reasons" do
      partial_index = Map.put(@project_id_index, :non_plain, [:predicate])

      actual = task_term(%{"task_project_id_$idx" => partial_index})
      target = task_term(%{"task_project_id_$idx" => @project_id_index})

      assert diff(actual, target) == [
               %{op: :drop_index, index: "task_project_id_$idx", non_plain: [:predicate]},
               %{
                 op: :create_index,
                 table: "task",
                 index: "task_project_id_$idx",
                 columns: ["project_id"],
                 nulls_distinct: true,
                 unique: false
               }
             ]
    end

    test "converges the role grant store's index under its old name by a rename and a create" do
      target =
        [Hologram.Test.Fixtures.Entity.Module14]
        |> Mapper.derive!([])
        |> then(&from_mapping(&1, IndexPlan.framework_plan(&1)))

      store = target.tables["hologram_role_grant"]
      unique_name = "hologram_role_grant_user_id_entity_type_entity_id_role_$uidx"
      entity_name = "hologram_role_grant_entity_type_entity_id_role_$idx"

      old_indexes =
        store.indexes
        |> Map.delete(entity_name)
        |> Map.delete(unique_name)
        |> Map.put("hologram_role_grant_$uidx", store.indexes[unique_name])

      actual = put_in(target.tables["hologram_role_grant"].indexes, old_indexes)

      assert diff(actual, target) == [
               %{
                 op: :rename_index,
                 table: "hologram_role_grant",
                 from: "hologram_role_grant_$uidx",
                 to: unique_name
               },
               %{
                 op: :create_index,
                 table: "hologram_role_grant",
                 index: entity_name,
                 columns: ["entity_type", "entity_id", "role"],
                 nulls_distinct: true,
                 unique: false
               }
             ]
    end

    test "keeps the name-keyed result with renames: false" do
      actual = task_term(%{"task_old_$idx" => @project_id_index})
      target = task_term(%{"task_new_$idx" => @project_id_index})

      assert diff(actual, target, renames: false) == [
               %{op: :drop_index, index: "task_old_$idx"},
               %{
                 op: :create_index,
                 table: "task",
                 index: "task_new_$idx",
                 columns: ["project_id"],
                 nulls_distinct: true,
                 unique: false
               }
             ]
    end
  end

  describe "from_mapping/1" do
    test "derives a table with columns and primary key per entity type" do
      assert from_mapping(app_mapping([Module1])) == %{
               tables: %{
                 "test_fixtures_entity_module1" => %{
                   columns: %{
                     "id" => %{type: "uuid", collation: nil, null: false},
                     "created_at" => %{type: "timestamptz", collation: nil, null: false},
                     "server_created_at" => %{type: "timestamptz", collation: nil, null: false},
                     "server_created_seq" => %{type: "int8", collation: nil, null: false},
                     "server_updated_at" => %{type: "timestamptz", collation: nil, null: false},
                     "server_updated_seq" => %{type: "int8", collation: nil, null: false},
                     "updated_at" => %{type: "timestamptz", collation: nil, null: false},
                     "$revisions" => %{type: "jsonb", collation: nil, null: false}
                   },
                   primary_key: %{
                     columns: ["id"],
                     constraint: "test_fixtures_entity_module1_$pk"
                   },
                   foreign_keys: %{},
                   indexes: %{}
                 }
               },
               enum_types: %{}
             }
    end

    test "carries a unique attribute's index" do
      indexes = table(Module19, "test_fixtures_entity_module19").indexes

      assert indexes == %{
               "test_fixtures_entity_module19_code_$uidx" => %{
                 columns: ["code"],
                 nulls_distinct: true,
                 unique: true
               },
               "test_fixtures_entity_module19_slug_$uidx" => %{
                 columns: ["slug"],
                 nulls_distinct: true,
                 unique: true
               }
             }
    end

    test "keys columns by name with type, collation, and nullability" do
      columns = table(Module2, "test_fixtures_entity_module2").columns

      # The same map as introspection_test reads back from Postgres - reconciliation diffs the
      # two, so they are identical on purpose and both must spell every column.
      # credo:disable-for-next-line Credo.Check.Design.DuplicatedCode
      assert columns == %{
               "id" => %{type: "uuid", collation: nil, null: false},
               "a" => %{type: "boolean", collation: nil, null: false},
               "b" => %{type: "int8", collation: nil, null: true},
               "c" => %{type: "text", collation: "C", null: false},
               "c_$sort" => %{type: "text", collation: "C", null: true},
               "c_$search" => %{type: "text", collation: "C", null: true},
               "created_at" => %{type: "timestamptz", collation: nil, null: false},
               "server_created_at" => %{type: "timestamptz", collation: nil, null: false},
               "server_created_seq" => %{type: "int8", collation: nil, null: false},
               "server_updated_at" => %{type: "timestamptz", collation: nil, null: false},
               "server_updated_seq" => %{type: "int8", collation: nil, null: false},
               "updated_at" => %{type: "timestamptz", collation: nil, null: false},
               "$revisions" => %{type: "jsonb", collation: nil, null: false}
             }
    end

    test "uses the derived enum type name as the column type" do
      columns = table(Module4, "test_fixtures_entity_module4").columns

      assert columns["c"] == %{
               type: "test_fixtures_entity_module4_c_$enum",
               collation: nil,
               null: false
             }
    end

    test "derives to-one reference columns on the owning table" do
      columns = table(Module3, "test_fixtures_entity_module3").columns

      assert columns["b_id"] == %{type: "uuid", collation: nil, null: true}
      assert columns["c_id"] == %{type: "uuid", collation: nil, null: false}
    end

    test "derives foreign keys keyed by owning column with restrict delete action" do
      foreign_keys = table(Module3, "test_fixtures_entity_module3").foreign_keys

      assert foreign_keys == %{
               "b_id" => %{
                 references: "test_fixtures_entity_module2",
                 on_delete: :restrict,
                 constraint: "test_fixtures_entity_module3_b_id_$fk"
               },
               "c_id" => %{
                 references: "test_fixtures_entity_module1",
                 on_delete: :restrict,
                 constraint: "test_fixtures_entity_module3_c_id_$fk"
               }
             }
    end

    test "derives the role grant store's user references with the no action delete action" do
      foreign_keys =
        [Hologram.Auth.RoleGrant, Hologram.Test.Fixtures.Entity.Module14]
        |> Mapper.derive!([])
        |> from_mapping()
        |> Map.fetch!(:tables)
        |> Map.fetch!("hologram_role_grant")
        |> Map.fetch!(:foreign_keys)

      assert foreign_keys == %{
               "granted_by_id" => %{
                 references: "test_fixtures_entity_module14",
                 on_delete: :no_action,
                 constraint: "hologram_role_grant_granted_by_id_$fk"
               },
               "user_id" => %{
                 references: "test_fixtures_entity_module14",
                 on_delete: :no_action,
                 constraint: "hologram_role_grant_user_id_$fk"
               }
             }
    end

    test "holds the index plan's indexes beside the model's, a join table's included" do
      schema =
        [Module3]
        |> Mapper.derive!([])
        |> then(&from_mapping(&1, IndexPlan.framework_plan(&1)))

      assert schema.tables["test_fixtures_entity_module3_a_$join"].indexes == %{
               "test_fixtures_entity_module3_a_$join_target_id_source_id_$idx" => %{
                 columns: ["target_id", "source_id"],
                 nulls_distinct: true,
                 unique: false
               }
             }

      assert schema.tables["test_fixtures_entity_module3"].indexes == %{
               "test_fixtures_entity_module3_b_id_$idx" => %{
                 columns: ["b_id"],
                 nulls_distinct: true,
                 unique: false
               },
               "test_fixtures_entity_module3_c_id_$idx" => %{
                 columns: ["c_id"],
                 nulls_distinct: true,
                 unique: false
               }
             }
    end

    test "derives join tables with fixed columns, composite primary key and foreign keys" do
      assert table(Module3, "test_fixtures_entity_module3_a_$join") == %{
               columns: %{
                 "source_id" => %{type: "uuid", collation: nil, null: false},
                 "target_id" => %{type: "uuid", collation: nil, null: false}
               },
               primary_key: %{
                 columns: ["source_id", "target_id"],
                 constraint: "test_fixtures_entity_module3_a_$join_$pk"
               },
               foreign_keys: %{
                 "source_id" => %{
                   references: "test_fixtures_entity_module3",
                   on_delete: :restrict,
                   constraint: "test_fixtures_entity_module3_a_$join_source_id_$fk"
                 },
                 "target_id" => %{
                   references: "test_fixtures_entity_module2",
                   on_delete: :restrict,
                   constraint: "test_fixtures_entity_module3_a_$join_target_id_$fk"
                 }
               },
               indexes: %{}
             }
    end

    test "collects enum types with values in declaration order" do
      enum_types =
        [Module4]
        |> app_mapping()
        |> from_mapping()
        |> Map.fetch!(:enum_types)

      assert enum_types == %{"test_fixtures_entity_module4_c_$enum" => ["x", "y"]}
    end

    test "collects tables across all entity types in the mapping" do
      table_names =
        [Module1, Module3]
        |> app_mapping()
        |> from_mapping()
        |> Map.fetch!(:tables)
        |> Map.keys()
        |> Enum.sort()

      assert table_names == [
               "test_fixtures_entity_module1",
               "test_fixtures_entity_module3",
               "test_fixtures_entity_module3_a_$join"
             ]
    end
  end
end
