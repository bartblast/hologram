defmodule Hologram.Database.SchemaTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Database.Schema

  alias Hologram.Database.Mapper
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module4

  defp table(entity_type, table_name) do
    [entity_type]
    |> Mapper.derive!()
    |> from_mapping()
    |> get_in([:tables, table_name])
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
                   }
                 }
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

    test "derives join tables with fixed columns and a composite primary key" do
      assert table(Module3, "test_fixtures_entity_module3_a_$join") == %{
               columns: %{
                 "source_id" => %{type: "uuid", collation: nil, null: false},
                 "target_id" => %{type: "uuid", collation: nil, null: false}
               },
               primary_key: %{
                 columns: ["source_id", "target_id"],
                 constraint: "test_fixtures_entity_module3_a_$join_$pk"
               }
             }
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
