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

      assert schema().tables["columnless"].columns == %{}
    end

    test "introspects the primary key with its constraint name" do
      create_statement = """
      CREATE TABLE "hologram_data"."pk_owner" (
        "id" uuid NOT NULL,
        CONSTRAINT "pk_owner_$pk" PRIMARY KEY ("id")
      )
      """

      {:ok, _result} = Connection.query(create_statement)

      assert schema().tables["pk_owner"].primary_key == %{
               columns: ["id"],
               constraint: "pk_owner_$pk"
             }
    end

    test "introspects composite primary keys in constraint column order" do
      create_statement = """
      CREATE TABLE "hologram_data"."composite_pk_owner" (
        "a" uuid NOT NULL,
        "b" uuid NOT NULL,
        CONSTRAINT "composite_pk_owner_$pk" PRIMARY KEY ("b", "a")
      )
      """

      {:ok, _result} = Connection.query(create_statement)

      assert schema().tables["composite_pk_owner"].primary_key == %{
               columns: ["b", "a"],
               constraint: "composite_pk_owner_$pk"
             }
    end

    test "derives nil primary key for tables without one" do
      create_statement = ~s{CREATE TABLE "hologram_data"."pk_less" ("x" int8)}

      {:ok, _result} = Connection.query(create_statement)

      assert schema().tables["pk_less"].primary_key == nil
    end

    test "introspects foreign keys keyed by owning column" do
      referencing_statement = """
      CREATE TABLE "hologram_data"."referencing" (
        "target_id" uuid,
        CONSTRAINT "referencing_target_id_$fk" FOREIGN KEY ("target_id")
          REFERENCES "hologram_data"."test_fixtures_entity_module1" ("id") ON DELETE RESTRICT
      )
      """

      {:ok, _result} = Connection.query(referencing_statement)

      assert schema().tables["referencing"].foreign_keys == %{
               "target_id" => %{
                 references: "test_fixtures_entity_module1",
                 on_delete: :restrict,
                 constraint: "referencing_target_id_$fk"
               }
             }
    end

    test "decodes delete actions beyond restrict" do
      referencing_statement = """
      CREATE TABLE "hologram_data"."cascading" (
        "target_id" uuid,
        CONSTRAINT "cascading_target_id_$fk" FOREIGN KEY ("target_id")
          REFERENCES "hologram_data"."test_fixtures_entity_module1" ("id") ON DELETE CASCADE
      )
      """

      {:ok, _result} = Connection.query(referencing_statement)

      assert schema().tables["cascading"].foreign_keys["target_id"].on_delete == :cascade
    end

    test "introspects indexes with their column order" do
      create_statement = ~s{CREATE TABLE "hologram_data"."indexed" ("a" int8, "b" int8)}

      index_statement =
        ~s{CREATE INDEX "indexed_b_a_$idx" ON "hologram_data"."indexed" ("b", "a")}

      {:ok, _result} = Connection.query(create_statement)
      {:ok, _result} = Connection.query(index_statement)

      assert schema().tables["indexed"].indexes == %{
               "indexed_b_a_$idx" => %{columns: ["b", "a"]}
             }
    end

    test "excludes primary-key-backing indexes" do
      create_statement = """
      CREATE TABLE "hologram_data"."pk_indexed" (
        "id" uuid NOT NULL,
        CONSTRAINT "pk_indexed_$pk" PRIMARY KEY ("id")
      )
      """

      {:ok, _result} = Connection.query(create_statement)

      assert schema().tables["pk_indexed"].indexes == %{}
    end

    test "introspects the fixture join table reverse index" do
      assert schema().tables["test_fixtures_entity_module3_a_$join"].indexes == %{
               "test_fixtures_entity_module3_a_$join_target_id_$idx" => %{
                 columns: ["target_id", "source_id"]
               }
             }
    end
  end
end
