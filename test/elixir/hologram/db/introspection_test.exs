defmodule Hologram.DB.IntrospectionTest do
  # async: false - the sandbox isolates data, not locks: DDL on shared relations
  # takes AccessExclusiveLock, which deadlocks with row locks that concurrent
  # sandboxed tests hold until rollback.
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.DB.Introspection

  alias Hologram.DB.Connection

  describe "schema/0" do
    test "lists the tables in the hologram_data schema" do
      table_names =
        schema().tables
        |> Map.keys()
        |> Enum.sort()

      assert table_names == [
               "hologram_role_grant",
               "test_fixtures_entity_module1",
               "test_fixtures_entity_module10",
               "test_fixtures_entity_module11",
               "test_fixtures_entity_module12",
               "test_fixtures_entity_module13",
               "test_fixtures_entity_module14",
               "test_fixtures_entity_module15",
               "test_fixtures_entity_module16",
               "test_fixtures_entity_module16_secrets_$join",
               "test_fixtures_entity_module17",
               "test_fixtures_entity_module18",
               "test_fixtures_entity_module19",
               "test_fixtures_entity_module2",
               "test_fixtures_entity_module20",
               "test_fixtures_entity_module21",
               "test_fixtures_entity_module22",
               "test_fixtures_entity_module23",
               "test_fixtures_entity_module3",
               "test_fixtures_entity_module3_a_$join",
               "test_fixtures_entity_module4",
               "test_fixtures_entity_module5",
               "test_fixtures_entity_module6",
               "test_fixtures_entity_module6_a_$join",
               "test_fixtures_entity_module7",
               "test_fixtures_entity_module8",
               "test_fixtures_entity_module9",
               "test_fixtures_entity_module9_a_$join",
               "test_fixtures_job_module1",
               "test_fixtures_job_module2",
               "test_fixtures_job_module3",
               "test_fixtures_policy_module1",
               "test_fixtures_policy_module2",
               "test_fixtures_policy_module3",
               "test_fixtures_policy_module3_children_$join",
               "test_fixtures_policy_module4",
               "test_fixtures_policy_module5"
             ]
    end

    test "introspects columns with type, collation, and nullability" do
      # The same map as the mapper projects in schema_test - reconciliation diffs the two, so
      # they are identical on purpose and both must spell every column.
      # credo:disable-for-next-line Credo.Check.Design.DuplicatedCode
      assert schema().tables["test_fixtures_entity_module2"].columns == %{
               "id" => %{type: "uuid", collation: nil, null: false},
               "a" => %{type: "boolean", collation: nil, null: false},
               "b" => %{type: "int8", collation: nil, null: true},
               "c" => %{type: "text", collation: "C", null: false},
               "c_$sort" => %{type: "text", collation: "C", null: true},
               "created_at" => %{type: "timestamptz", collation: nil, null: false},
               "updated_at" => %{type: "timestamptz", collation: nil, null: false},
               "$revisions" => %{type: "jsonb", collation: nil, null: false}
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
               "indexed_b_a_$idx" => %{columns: ["b", "a"], nulls_distinct: true, unique: false}
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
                 columns: ["target_id", "source_id"],
                 nulls_distinct: true,
                 unique: false
               }
             }
    end

    test "introspects the role grant store's user references as no action" do
      foreign_keys = schema().tables["hologram_role_grant"].foreign_keys

      assert foreign_keys["user_id"].on_delete == :no_action
      assert foreign_keys["granted_by_id"].on_delete == :no_action
    end

    test "introspects the role grant unique index comparing nulls as values" do
      assert schema().tables["hologram_role_grant"].indexes["hologram_role_grant_$uidx"] == %{
               columns: ["user_id", "entity_type", "entity_id", "role"],
               nulls_distinct: false,
               unique: true
             }
    end

    test "introspects a unique attribute's index as unique" do
      indexes = schema().tables["test_fixtures_entity_module19"].indexes

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

    test "introspects enum types with their values" do
      assert schema().enum_types == %{
               "hologram_role_grant_entity_type_$enum" => [
                 "Hologram.Test.Fixtures.Entity.Module1",
                 "Hologram.Test.Fixtures.Entity.Module10",
                 "Hologram.Test.Fixtures.Entity.Module11",
                 "Hologram.Test.Fixtures.Entity.Module12",
                 "Hologram.Test.Fixtures.Entity.Module13",
                 "Hologram.Test.Fixtures.Entity.Module14",
                 "Hologram.Test.Fixtures.Entity.Module15",
                 "Hologram.Test.Fixtures.Entity.Module16",
                 "Hologram.Test.Fixtures.Entity.Module17",
                 "Hologram.Test.Fixtures.Entity.Module18",
                 "Hologram.Test.Fixtures.Entity.Module19",
                 "Hologram.Test.Fixtures.Entity.Module2",
                 "Hologram.Test.Fixtures.Entity.Module20",
                 "Hologram.Test.Fixtures.Entity.Module21",
                 "Hologram.Test.Fixtures.Entity.Module22",
                 "Hologram.Test.Fixtures.Entity.Module23",
                 "Hologram.Test.Fixtures.Entity.Module3",
                 "Hologram.Test.Fixtures.Entity.Module4",
                 "Hologram.Test.Fixtures.Entity.Module5",
                 "Hologram.Test.Fixtures.Entity.Module6",
                 "Hologram.Test.Fixtures.Entity.Module7",
                 "Hologram.Test.Fixtures.Entity.Module8",
                 "Hologram.Test.Fixtures.Entity.Module9",
                 "Hologram.Test.Fixtures.Job.Module1",
                 "Hologram.Test.Fixtures.Job.Module2",
                 "Hologram.Test.Fixtures.Job.Module3",
                 "Hologram.Test.Fixtures.Policy.Module1",
                 "Hologram.Test.Fixtures.Policy.Module2",
                 "Hologram.Test.Fixtures.Policy.Module3",
                 "Hologram.Test.Fixtures.Policy.Module4",
                 "Hologram.Test.Fixtures.Policy.Module5"
               ],
               "hologram_role_grant_role_$enum" => [
                 "Hologram.Test.Fixtures.Role.Module1",
                 "Hologram.Test.Fixtures.Role.Module2",
                 "admin",
                 "editor",
                 "maintainer",
                 "member",
                 "owner",
                 "viewer"
               ],
               "test_fixtures_entity_module17_priority_$enum" => ["low", "medium", "high"],
               "test_fixtures_job_module1_status_$enum" => [
                 "queued",
                 "running",
                 "done",
                 "failed"
               ],
               "test_fixtures_job_module2_status_$enum" => [
                 "queued",
                 "running",
                 "done",
                 "failed"
               ],
               "test_fixtures_job_module3_outcome_$enum" => [
                 "create_next",
                 "create_row",
                 "error",
                 "exit",
                 "garbage",
                 "ok",
                 "ok_tuple",
                 "raise",
                 "record_actor",
                 "record_order",
                 "throw"
               ],
               "test_fixtures_job_module3_status_$enum" => [
                 "queued",
                 "running",
                 "done",
                 "failed"
               ],
               "test_fixtures_entity_module4_c_$enum" => ["x", "y"]
             }
    end

    test "introspects enum values in sort order after positioned additions" do
      add_statement =
        ~s(ALTER TYPE "hologram_data"."test_fixtures_entity_module4_c_$enum" ) <>
          "ADD VALUE 'w' BEFORE 'x'"

      {:ok, _result} = Connection.query(add_statement)

      assert schema().enum_types["test_fixtures_entity_module4_c_$enum"] == ["w", "x", "y"]
    end

    test "introspects an enum type that has no values yet" do
      create_statement = ~s{CREATE TYPE "hologram_data"."empty_$enum" AS ENUM ()}

      {:ok, _result} = Connection.query(create_statement)

      assert schema().enum_types["empty_$enum"] == []
    end

    test "excludes enum types outside the hologram_data schema" do
      create_statement = ~s{CREATE TYPE "public"."alien_$enum" AS ENUM ('a')}

      {:ok, _result} = Connection.query(create_statement)

      refute Map.has_key?(schema().enum_types, "alien_$enum")
    end
  end
end
