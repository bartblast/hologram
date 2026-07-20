defmodule Hologram.Database.SchemaTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Database.Schema

  alias Hologram.Database.Mapper
  alias Hologram.Test.Fixtures.Entity.Module1
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

  describe "from_mapping/1" do
    test "derives a table with columns and primary key per entity type" do
      assert from_mapping(Mapper.derive!([Module1])) == %{
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

    test "keys columns by name with type, collation, and nullability" do
      columns = table(Module2, "test_fixtures_entity_module2").columns

      assert columns == %{
               "id" => %{type: "uuid", collation: nil, null: false},
               "a" => %{type: "boolean", collation: nil, null: false},
               "b" => %{type: "int8", collation: nil, null: true},
               "c" => %{type: "text", collation: "C", null: false},
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

    test "derives an index per reference column" do
      indexes = table(Module3, "test_fixtures_entity_module3").indexes

      assert indexes == %{
               "test_fixtures_entity_module3_b_id_$idx" => %{columns: ["b_id"]},
               "test_fixtures_entity_module3_c_id_$idx" => %{columns: ["c_id"]}
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
                   columns: ["target_id", "source_id"]
                 }
               }
             }
    end

    test "collects enum types with values in declaration order" do
      enum_types =
        [Module4]
        |> Mapper.derive!()
        |> from_mapping()
        |> Map.fetch!(:enum_types)

      assert enum_types == %{"test_fixtures_entity_module4_c_$enum" => ["x", "y"]}
    end

    test "collects tables across all entity types in the mapping" do
      table_names =
        [Module1, Module3]
        |> Mapper.derive!()
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
