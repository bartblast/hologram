defmodule Hologram.Database.IntrospectionTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.Database.Introspection

  alias Hologram.Database.Connection

  describe "schema/0" do
    test "lists the tables in the hologram_data schema" do
      table_names =
        schema().tables
        |> Map.keys()
        |> Enum.sort()

      assert table_names == [
               "test_fixtures_entity_module1",
               "test_fixtures_entity_module2",
               "test_fixtures_entity_module3",
               "test_fixtures_entity_module3_a_$join",
               "test_fixtures_entity_module4"
             ]
    end

    test "introspects columns with type, collation, and nullability" do
      assert schema().tables["test_fixtures_entity_module2"].columns == %{
               "id" => %{type: "uuid", collation: nil, null: false},
               "a" => %{type: "boolean", collation: nil, null: false},
               "b" => %{type: "int8", collation: nil, null: true},
               "c" => %{type: "text", collation: "C", null: false},
               "created_at" => %{type: "timestamptz", collation: nil, null: false},
               "updated_at" => %{type: "timestamptz", collation: nil, null: false}
             }
    end

    test "introspects enum columns with the derived enum type name" do
      columns = schema().tables["test_fixtures_entity_module4"].columns

      assert columns["c"] == %{
               type: "test_fixtures_entity_module4_c_$enum",
               collation: nil,
               null: false
             }
    end

    test "excludes dropped-column tombstones" do
      drop_statement =
        ~s(ALTER TABLE "hologram_data"."test_fixtures_entity_module2" DROP COLUMN "b")

      {:ok, _result} = Connection.query(drop_statement)

      refute Map.has_key?(schema().tables["test_fixtures_entity_module2"].columns, "b")
    end

    test "excludes tables outside the hologram_data schema" do
      create_statement = ~s{CREATE TABLE "public"."introspection_alien" ("x" int8)}

      {:ok, _result} = Connection.query(create_statement)

      refute Map.has_key?(schema().tables, "introspection_alien")
    end

    test "lists tables with no remaining columns" do
      create_statement = ~s{CREATE TABLE "hologram_data"."columnless" ("x" int8)}
      drop_statement = ~s(ALTER TABLE "hologram_data"."columnless" DROP COLUMN "x")

      {:ok, _result} = Connection.query(create_statement)
      {:ok, _result} = Connection.query(drop_statement)

      assert schema().tables["columnless"] == %{columns: %{}}
    end
  end
end
