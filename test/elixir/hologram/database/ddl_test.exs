defmodule Hologram.Database.DDLTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Database.DDL

  describe "statements/1 for create_table" do
    test "renders columns in canonical order with the named primary key constraint" do
      op = %{
        op: :create_table,
        table: "task",
        columns: %{
          "id" => %{type: "uuid", collation: nil, null: false},
          "name" => %{type: "text", collation: "C", null: false},
          "done" => %{type: "boolean", collation: nil, null: true},
          "created_at" => %{type: "timestamptz", collation: nil, null: false},
          "updated_at" => %{type: "timestamptz", collation: nil, null: false}
        },
        primary_key: %{columns: ["id"], constraint: "task_$pk"}
      }

      expected_statement = """
      CREATE TABLE "hologram_data"."task" (
        "id" uuid NOT NULL,
        "done" boolean,
        "name" text COLLATE "C" NOT NULL,
        "created_at" timestamptz NOT NULL,
        "updated_at" timestamptz NOT NULL,
        CONSTRAINT "task_$pk" PRIMARY KEY ("id")
      )\
      """

      assert statements(op) == [expected_statement]
    end

    test "schema-qualifies derived enum column types" do
      op = %{
        op: :create_table,
        table: "task",
        columns: %{
          "id" => %{type: "uuid", collation: nil, null: false},
          "status" => %{type: "task_status_$enum", collation: nil, null: false}
        },
        primary_key: %{columns: ["id"], constraint: "task_$pk"}
      }

      expected_statement = """
      CREATE TABLE "hologram_data"."task" (
        "id" uuid NOT NULL,
        "status" "hologram_data"."task_status_$enum" NOT NULL,
        CONSTRAINT "task_$pk" PRIMARY KEY ("id")
      )\
      """

      assert statements(op) == [expected_statement]
    end

    test "renders composite primary keys" do
      op = %{
        op: :create_table,
        table: "task_tags_$join",
        columns: %{
          "source_id" => %{type: "uuid", collation: nil, null: false},
          "target_id" => %{type: "uuid", collation: nil, null: false}
        },
        primary_key: %{columns: ["source_id", "target_id"], constraint: "task_tags_$join_$pk"}
      }

      expected_statement = """
      CREATE TABLE "hologram_data"."task_tags_$join" (
        "source_id" uuid NOT NULL,
        "target_id" uuid NOT NULL,
        CONSTRAINT "task_tags_$join_$pk" PRIMARY KEY ("source_id", "target_id")
      )\
      """

      assert statements(op) == [expected_statement]
    end
  end

  describe "statements/1 for drop_table" do
    test "renders a schema-qualified drop" do
      op = %{op: :drop_table, table: "task"}

      assert statements(op) == [~s(DROP TABLE "hologram_data"."task")]
    end
  end

  describe "statements/1 for add_column" do
    test "renders the column definition with collation and nullability" do
      op = %{
        op: :add_column,
        table: "task",
        column: "name",
        definition: %{type: "text", collation: "C", null: false}
      }

      assert statements(op) == [
               ~s(ALTER TABLE "hologram_data"."task" ADD COLUMN "name" text COLLATE "C" NOT NULL)
             ]
    end

    test "renders optional columns without the NOT NULL clause" do
      op = %{
        op: :add_column,
        table: "task",
        column: "done",
        definition: %{type: "boolean", collation: nil, null: true}
      }

      assert statements(op) == [
               ~s(ALTER TABLE "hologram_data"."task" ADD COLUMN "done" boolean)
             ]
    end
  end

  describe "statements/1 for drop_column" do
    test "renders the column drop" do
      op = %{op: :drop_column, table: "task", column: "name"}

      assert statements(op) == [~s(ALTER TABLE "hologram_data"."task" DROP COLUMN "name")]
    end
  end

  describe "statements/1 for add_foreign_key" do
    test "renders a named constraint referencing the target id with the delete action" do
      op = %{
        op: :add_foreign_key,
        table: "task",
        column: "project_id",
        references: "project",
        on_delete: :restrict,
        constraint: "task_project_id_$fk"
      }

      assert statements(op) == [
               ~s(ALTER TABLE "hologram_data"."task" ) <>
                 ~s(ADD CONSTRAINT "task_project_id_$fk" ) <>
                 ~s{FOREIGN KEY ("project_id") } <>
                 ~s{REFERENCES "hologram_data"."project" ("id") } <>
                 "ON DELETE RESTRICT"
             ]
    end
  end

  describe "statements/1 for drop_foreign_key" do
    test "renders the constraint drop" do
      op = %{op: :drop_foreign_key, table: "task", constraint: "task_project_id_$fk"}

      assert statements(op) == [
               ~s(ALTER TABLE "hologram_data"."task" DROP CONSTRAINT "task_project_id_$fk")
             ]
    end
  end

  describe "statements/1 for rename_constraint" do
    test "renders the constraint rename" do
      op = %{op: :rename_constraint, table: "task", from: "task_pkey", to: "task_$pk"}

      assert statements(op) == [
               ~s(ALTER TABLE "hologram_data"."task" ) <>
                 ~s(RENAME CONSTRAINT "task_pkey" TO "task_$pk")
             ]
    end
  end

  describe "statements/1 for create_index" do
    test "renders a named index over its columns" do
      op = %{
        op: :create_index,
        table: "task",
        index: "task_project_id_$idx",
        columns: ["project_id"]
      }

      assert statements(op) == [
               ~s{CREATE INDEX "task_project_id_$idx" ON "hologram_data"."task" ("project_id")}
             ]
    end

    test "renders multi-column indexes in column order" do
      op = %{
        op: :create_index,
        table: "task_tags_$join",
        index: "task_tags_$join_target_id_$idx",
        columns: ["target_id", "source_id"]
      }

      assert statements(op) == [
               ~s(CREATE INDEX "task_tags_$join_target_id_$idx" ) <>
                 ~s{ON "hologram_data"."task_tags_$join" ("target_id", "source_id")}
             ]
    end
  end

  describe "statements/1 for drop_index" do
    test "renders the schema-qualified index drop" do
      op = %{op: :drop_index, index: "task_project_id_$idx"}

      assert statements(op) == [~s(DROP INDEX "hologram_data"."task_project_id_$idx")]
    end
  end

  describe "statements/1 for alter_column" do
    test "renders SET NOT NULL when the column becomes required" do
      op = %{
        op: :alter_column,
        table: "task",
        column: "name",
        before: %{type: "text", collation: "C", null: true},
        after: %{type: "text", collation: "C", null: false}
      }

      assert statements(op) == [
               ~s(ALTER TABLE "hologram_data"."task" ALTER COLUMN "name" SET NOT NULL)
             ]
    end

    test "renders DROP NOT NULL when the column becomes optional" do
      op = %{
        op: :alter_column,
        table: "task",
        column: "name",
        before: %{type: "text", collation: "C", null: false},
        after: %{type: "text", collation: "C", null: true}
      }

      assert statements(op) == [
               ~s(ALTER TABLE "hologram_data"."task" ALTER COLUMN "name" DROP NOT NULL)
             ]
    end

    test "renders a type change with a USING cast" do
      op = %{
        op: :alter_column,
        table: "task",
        column: "count",
        before: %{type: "int8", collation: nil, null: false},
        after: %{type: "float8", collation: nil, null: false}
      }

      assert statements(op) == [
               ~s(ALTER TABLE "hologram_data"."task" ) <>
                 ~s(ALTER COLUMN "count" TYPE float8 USING "count"::float8)
             ]
    end

    test "renders a type change to a collated type with the collation" do
      op = %{
        op: :alter_column,
        table: "task",
        column: "count",
        before: %{type: "int8", collation: nil, null: false},
        after: %{type: "text", collation: "C", null: false}
      }

      assert statements(op) == [
               ~s(ALTER TABLE "hologram_data"."task" ) <>
                 ~s(ALTER COLUMN "count" TYPE text COLLATE "C" USING "count"::text)
             ]
    end

    test "combines type and nullability actions in one statement" do
      op = %{
        op: :alter_column,
        table: "task",
        column: "count",
        before: %{type: "int8", collation: nil, null: false},
        after: %{type: "float8", collation: nil, null: true}
      }

      assert statements(op) == [
               ~s(ALTER TABLE "hologram_data"."task" ) <>
                 ~s(ALTER COLUMN "count" TYPE float8 USING "count"::float8, ) <>
                 ~s(ALTER COLUMN "count" DROP NOT NULL)
             ]
    end
  end
end
