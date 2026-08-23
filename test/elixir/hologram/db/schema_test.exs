defmodule Hologram.DB.SchemaTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.DB.Schema

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
    |> Mapper.derive!()
    |> Map.drop([Hologram.Auth.RoleGrant])
  end

  defp table(entity_type, table_name) do
    [entity_type]
    |> Mapper.derive!()
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

      assert_error ArgumentError, expected_msg, fn ->
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
          "task_old_$idx" => %{columns: ["legacy"], nulls_distinct: true, unique: false}
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
          "task_new_$idx" => %{columns: ["done"], nulls_distinct: true, unique: false}
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

  describe "from_mapping/1" do
    test "derives a table with columns and primary key per entity type" do
      assert from_mapping(app_mapping([Module1])) == %{
               tables: %{
                 "test_fixtures_entity_module1" => %{
                   columns: %{
                     "id" => %{type: "uuid", collation: nil, null: false},
                     "created_at" => %{type: "timestamptz", collation: nil, null: false},
                     "updated_at" => %{type: "timestamptz", collation: nil, null: false}
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

    test "carries a unique attribute's index beside the sort-key companion's" do
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
               },
               "test_fixtures_entity_module19_code_$sort_$idx" => %{
                 columns: ["code_$sort"],
                 nulls_distinct: true,
                 unique: false
               },
               "test_fixtures_entity_module19_slug_$sort_$idx" => %{
                 columns: ["slug_$sort"],
                 nulls_distinct: true,
                 unique: false
               }
             }
    end

    test "keys columns by name with type, collation, and nullability" do
      columns = table(Module2, "test_fixtures_entity_module2").columns

      assert columns == %{
               "id" => %{type: "uuid", collation: nil, null: false},
               "a" => %{type: "boolean", collation: nil, null: false},
               "b" => %{type: "int8", collation: nil, null: true},
               "c" => %{type: "text", collation: "C", null: false},
               "c_$sort" => %{type: "text", collation: "C", null: true},
               "created_at" => %{type: "timestamptz", collation: nil, null: false},
               "updated_at" => %{type: "timestamptz", collation: nil, null: false}
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
        |> Mapper.derive!()
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

    test "derives an index per reference column" do
      indexes = table(Module3, "test_fixtures_entity_module3").indexes

      assert indexes == %{
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

    test "derives join tables with fixed columns, composite primary key, foreign keys, and reverse index" do
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
               indexes: %{
                 "test_fixtures_entity_module3_a_$join_target_id_$idx" => %{
                   columns: ["target_id", "source_id"],
                   nulls_distinct: true,
                   unique: false
                 }
               }
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
