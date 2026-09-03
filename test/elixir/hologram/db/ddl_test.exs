defmodule Hologram.DB.DDLTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.DB.DDL

  describe "built_index_check_statement/1" do
    test "counts the valid indexes carrying the name" do
      expected =
        normalize_newlines("""
        SELECT COUNT(*)
        FROM pg_catalog.pg_index i
        JOIN pg_catalog.pg_class c ON c.oid = i.indexrelid
        JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'hologram_data' AND c.relname = 'task_project_id_$idx' AND i.indisvalid = TRUE\
        """)

      assert normalize_newlines(built_index_check_statement("task_project_id_$idx")) == expected
    end

    test "escapes a quote in the index name" do
      statement = normalize_newlines(built_index_check_statement("od'd_$idx"))

      assert statement =~ ~s(c.relname = 'od''d_$idx')
    end
  end

  describe "cast_check_statement/4" do
    test "counts rows with fractional parts or an out-of-range magnitude for float8 to int8" do
      assert cast_check_statement("task", "score", "float8", "int8") ==
               ~s/SELECT COUNT(*) FROM "hologram_data"."task" / <>
                 ~s/WHERE "score" <> trunc("score") / <>
                 ~s/OR "score" >= 9223372036854775808::float8 / <>
                 ~s/OR "score" < -9223372036854775808::float8/
    end

    test "counts rows with non-integer or out-of-range text for text to int8" do
      assert cast_check_statement("task", "count", "text", "int8") ==
               ~s/SELECT COUNT(*) FROM "hologram_data"."task" WHERE / <>
                 ~s/CASE WHEN NOT ("count" ~ '^\\s*[+-]?[0-9]+\\s*$') THEN true / <>
                 ~s/WHEN "count" ~ '^\\s*[+-]?0*[1-9][0-9]{19,}\\s*$' THEN true / <>
                 ~s/ELSE "count"::numeric NOT BETWEEN / <>
                 ~s/-9223372036854775808 AND 9223372036854775807 END/
    end

    test "counts rows with non-numeric or out-of-range text for text to float8" do
      assert cast_check_statement("task", "score", "text", "float8") ==
               ~s/SELECT COUNT(*) FROM "hologram_data"."task" WHERE / <>
                 ~s/CASE WHEN "score" ~* '^\\s*[+-]?(inf(inity)?|nan)\\s*$' THEN false / <>
                 ~s/WHEN NOT ("score" ~ / <>
                 ~s/'^\\s*[+-]?([0-9]+(\\.[0-9]*)?|\\.[0-9]+)([eE][+-]?[0-9]+)?\\s*$') / <>
                 ~s/THEN true / <>
                 ~s/WHEN "score" ~ '^\\s*[+-]?(0+(\\.0*)?|\\.0+)([eE][+-]?[0-9]+)?\\s*$' / <>
                 ~s/THEN false / <>
                 ~s/WHEN length("score") > 2000 THEN true / <>
                 ~s/WHEN "score" ~ '[eE][+-]?[0-9]{4,}\\s*$' THEN true / <>
                 ~s/ELSE abs("score"::numeric) > 1.7976931348623157e308 / <>
                 ~s/OR abs("score"::numeric) < 4.9406564584124654e-324 END/
    end

    test "counts rows with a time part for timestamptz to date" do
      assert cast_check_statement("task", "due_at", "timestamptz", "date") ==
               ~s{SELECT COUNT(*) FROM "hologram_data"."task" } <>
                 ~s{WHERE "due_at" <> date_trunc('day', "due_at")}
    end
  end

  describe "cast_class/2" do
    # Every ordered pair of the eight builtin types, as a literal table: 64 cells, so no
    # combination can be added to the type set and quietly land in :unsupported unnoticed.
    # Read down the FROM column, across the TO row.
    test "classifies every pair of builtin types" do
      classes = %{
        {"boolean", "boolean"} => :safe,
        {"boolean", "date"} => :unsupported,
        {"boolean", "float8"} => :unsupported,
        {"boolean", "int8"} => :unsupported,
        {"boolean", "text"} => :safe,
        {"boolean", "time"} => :unsupported,
        {"boolean", "timestamptz"} => :unsupported,
        {"boolean", "uuid"} => :unsupported,
        {"date", "boolean"} => :unsupported,
        {"date", "date"} => :safe,
        {"date", "float8"} => :unsupported,
        {"date", "int8"} => :unsupported,
        {"date", "text"} => :safe,
        {"date", "time"} => :unsupported,
        {"date", "timestamptz"} => :safe,
        {"date", "uuid"} => :unsupported,
        {"float8", "boolean"} => :unsupported,
        {"float8", "date"} => :unsupported,
        {"float8", "float8"} => :safe,
        {"float8", "int8"} => :data_dependent,
        {"float8", "text"} => :safe,
        {"float8", "time"} => :unsupported,
        {"float8", "timestamptz"} => :unsupported,
        {"float8", "uuid"} => :unsupported,
        {"int8", "boolean"} => :unsupported,
        {"int8", "date"} => :unsupported,
        {"int8", "float8"} => :safe,
        {"int8", "int8"} => :safe,
        {"int8", "text"} => :safe,
        {"int8", "time"} => :unsupported,
        {"int8", "timestamptz"} => :unsupported,
        {"int8", "uuid"} => :unsupported,
        {"text", "boolean"} => :unsupported,
        {"text", "date"} => :unsupported,
        {"text", "float8"} => :data_dependent,
        {"text", "int8"} => :data_dependent,
        {"text", "text"} => :safe,
        {"text", "time"} => :unsupported,
        {"text", "timestamptz"} => :unsupported,
        {"text", "uuid"} => :unsupported,
        {"time", "boolean"} => :unsupported,
        {"time", "date"} => :unsupported,
        {"time", "float8"} => :unsupported,
        {"time", "int8"} => :unsupported,
        {"time", "text"} => :safe,
        {"time", "time"} => :safe,
        {"time", "timestamptz"} => :unsupported,
        {"time", "uuid"} => :unsupported,
        {"timestamptz", "boolean"} => :unsupported,
        {"timestamptz", "date"} => :data_dependent,
        {"timestamptz", "float8"} => :unsupported,
        {"timestamptz", "int8"} => :unsupported,
        {"timestamptz", "text"} => :safe,
        {"timestamptz", "time"} => :unsupported,
        {"timestamptz", "timestamptz"} => :safe,
        {"timestamptz", "uuid"} => :unsupported,
        {"uuid", "boolean"} => :unsupported,
        {"uuid", "date"} => :unsupported,
        {"uuid", "float8"} => :unsupported,
        {"uuid", "int8"} => :unsupported,
        {"uuid", "text"} => :safe,
        {"uuid", "time"} => :unsupported,
        {"uuid", "timestamptz"} => :unsupported,
        {"uuid", "uuid"} => :safe
      }

      actual =
        Map.new(classes, fn {{from_type, to_type}, _class} ->
          {{from_type, to_type}, cast_class(from_type, to_type)}
        end)

      assert actual == classes
    end

    # A derived enum type is not in the builtin set, and only one direction is automatic:
    # text is the universal sink, and nothing casts INTO an enum without knowing its values.
    test "classifies a derived enum type to text as safe and back as unsupported" do
      assert cast_class("task_status_$enum", "text") == :safe
      assert cast_class("task_status_$enum", "task_status_$enum") == :safe
      assert cast_class("text", "task_status_$enum") == :unsupported
      assert cast_class("int8", "task_status_$enum") == :unsupported
    end

    # Every pair the table above marks :data_dependent has a check statement, and no other
    # pair does - the two are one fact. A pair in only one of them would raise at apply time
    # for want of a clause, or refuse rows that nothing ever checks.
    test "gives every data-dependent pair a check statement, and only those" do
      builtin_types = ["boolean", "date", "float8", "int8", "text", "time", "timestamptz", "uuid"]
      pairs = for from_type <- builtin_types, to_type <- builtin_types, do: {from_type, to_type}

      {data_dependent, others} =
        Enum.split_with(pairs, fn {from_type, to_type} ->
          cast_class(from_type, to_type) == :data_dependent
        end)

      Enum.each(data_dependent, fn {from_type, to_type} ->
        assert is_binary(cast_check_statement("task", "value", from_type, to_type))
      end)

      Enum.each(others, fn {from_type, to_type} ->
        assert_raise FunctionClauseError, fn ->
          cast_check_statement("task", "value", from_type, to_type)
        end
      end)
    end
  end

  describe "duplicate_check_statement/3" do
    test "counts the duplicate key groups, nulls compared as values" do
      statement = duplicate_check_statement("task", ["project_id", "slug"], false)

      assert statement ==
               ~s{SELECT COUNT(*) FROM (SELECT 1 FROM "hologram_data"."task" } <>
                 ~s{GROUP BY "project_id", "slug" HAVING COUNT(*) > 1) AS duplicates}
    end

    test "skips the rows holding nulls when nulls are distinct" do
      statement = duplicate_check_statement("task", ["slug"], true)

      assert statement ==
               ~s{SELECT COUNT(*) FROM (SELECT 1 FROM "hologram_data"."task" } <>
                 ~s{WHERE "slug" IS NOT NULL GROUP BY "slug" HAVING COUNT(*) > 1) AS duplicates}
    end
  end

  describe "enum_values_check_statement/3" do
    test "counts rows holding any of the given values" do
      assert enum_values_check_statement("task", "status", ["wip", "blocked"]) ==
               ~s{SELECT COUNT(*) FROM "hologram_data"."task" } <>
                 ~s{WHERE "status"::text IN ('wip', 'blocked')}
    end
  end

  describe "invalid_index_check_statement/1" do
    test "counts the invalid indexes carrying the name" do
      expected =
        normalize_newlines("""
        SELECT COUNT(*)
        FROM pg_catalog.pg_index i
        JOIN pg_catalog.pg_class c ON c.oid = i.indexrelid
        JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'hologram_data' AND c.relname = 'task_project_id_$idx' AND i.indisvalid = FALSE\
        """)

      assert normalize_newlines(invalid_index_check_statement("task_project_id_$idx")) ==
               expected
    end

    test "escapes a quote in the index name" do
      statement = normalize_newlines(invalid_index_check_statement("od'd_$idx"))

      assert statement =~ ~s(c.relname = 'od''d_$idx')
    end
  end

  describe "invalid_indexes_statement/0" do
    test "lists the invalid indexes of the data schema" do
      statement = normalize_newlines(invalid_indexes_statement())

      assert statement =~ "SELECT ic.relname"
      assert statement =~ "WHERE n.nspname = 'hologram_data' AND NOT i.indisvalid"
    end
  end

  describe "null_check_statement/2" do
    test "counts rows with a NULL in the column" do
      assert null_check_statement("task", "subtitle") ==
               ~s{SELECT COUNT(*) FROM "hologram_data"."task" WHERE "subtitle" IS NULL}
    end
  end

  describe "reindex_statement/1" do
    test "rebuilds the index in place, concurrently" do
      assert reindex_statement("task_project_id_$idx") ==
               ~s{REINDEX INDEX CONCURRENTLY "hologram_data"."task_project_id_$idx"}
    end
  end

  describe "rows_check_statement/1" do
    test "counts the rows of the table" do
      assert rows_check_statement("task") ==
               ~s{SELECT COUNT(*) FROM "hologram_data"."task"}
    end
  end

  describe "statements/1 for add_column" do
    test "renders a time column type without schema-qualifying it" do
      op = %{
        op: :add_column,
        table: "task",
        column: "opens_at",
        definition: %{type: "time", collation: nil, null: true}
      }

      assert statements(op) == [
               ~s(ALTER TABLE "hologram_data"."task" ADD COLUMN "opens_at" time)
             ]
    end

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

  describe "statements/1 for add_enum_value" do
    test "renders a plain append for nil position" do
      op = %{
        op: :add_enum_value,
        enum_type: "task_status_$enum",
        value: "archived",
        position: nil
      }

      assert statements(op) == [
               ~s(ALTER TYPE "hologram_data"."task_status_$enum" ADD VALUE 'archived')
             ]
    end

    test "renders the BEFORE anchor for positioned values" do
      op = %{
        op: :add_enum_value,
        enum_type: "task_status_$enum",
        value: "draft",
        position: {:before, "todo"}
      }

      assert statements(op) == [
               ~s(ALTER TYPE "hologram_data"."task_status_$enum" ) <>
                 "ADD VALUE 'draft' BEFORE 'todo'"
             ]
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

    test "renders the no action delete action" do
      op = %{
        op: :add_foreign_key,
        table: "hologram_role_grant",
        column: "user_id",
        references: "user",
        on_delete: :no_action,
        constraint: "hologram_role_grant_user_id_$fk"
      }

      assert statements(op) == [
               ~s(ALTER TABLE "hologram_data"."hologram_role_grant" ) <>
                 ~s(ADD CONSTRAINT "hologram_role_grant_user_id_$fk" ) <>
                 ~s{FOREIGN KEY ("user_id") } <>
                 ~s{REFERENCES "hologram_data"."user" ("id") } <>
                 "ON DELETE NO ACTION"
             ]
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

  describe "statements/1 for create_enum_type" do
    test "renders the type with its values in order" do
      op = %{op: :create_enum_type, enum_type: "task_status_$enum", values: ["todo", "done"]}

      assert statements(op) == [
               ~s{CREATE TYPE "hologram_data"."task_status_$enum" AS ENUM ('todo', 'done')}
             ]
    end

    test "escapes single quotes in values" do
      op = %{op: :create_enum_type, enum_type: "task_status_$enum", values: ["won't do"]}

      assert statements(op) == [
               ~s{CREATE TYPE "hologram_data"."task_status_$enum" AS ENUM ('won''t do')}
             ]
    end
  end

  describe "statements/1 for create_index" do
    test "renders a named index over its columns" do
      op = %{
        op: :create_index,
        table: "task",
        index: "task_project_id_$idx",
        columns: ["project_id"],
        nulls_distinct: true,
        unique: false
      }

      assert statements(op) == [
               ~s{CREATE INDEX "task_project_id_$idx" ON "hologram_data"."task" ("project_id")}
             ]
    end

    test "renders a concurrent build when the op asks for one" do
      op = %{
        op: :create_index,
        table: "task",
        index: "task_project_id_$idx",
        columns: ["project_id"],
        nulls_distinct: true,
        unique: false,
        concurrently: true
      }

      assert statements(op) == [
               ~s{CREATE INDEX CONCURRENTLY "task_project_id_$idx" } <>
                 ~s{ON "hologram_data"."task" ("project_id")}
             ]
    end

    test "renders multi-column indexes in column order" do
      op = %{
        op: :create_index,
        table: "task_tags_$join",
        index: "task_tags_$join_target_id_$idx",
        columns: ["target_id", "source_id"],
        nulls_distinct: true,
        unique: false
      }

      assert statements(op) == [
               ~s(CREATE INDEX "task_tags_$join_target_id_$idx" ) <>
                 ~s{ON "hologram_data"."task_tags_$join" ("target_id", "source_id")}
             ]
    end

    test "renders unique indexes comparing nulls as values" do
      op = %{
        op: :create_index,
        table: "hologram_role_grant",
        index: "hologram_role_grant_$uidx",
        columns: ["user_id", "resource_type", "entity_id", "role"],
        nulls_distinct: false,
        unique: true
      }

      assert statements(op) == [
               ~s(CREATE UNIQUE INDEX "hologram_role_grant_$uidx" ) <>
                 ~s{ON "hologram_data"."hologram_role_grant" } <>
                 ~s{("user_id", "resource_type", "entity_id", "role") NULLS NOT DISTINCT}
             ]
    end
  end

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

      expected_statement =
        normalize_newlines("""
        CREATE TABLE "hologram_data"."task" (
          "id" uuid NOT NULL,
          "done" boolean,
          "name" text COLLATE "C" NOT NULL,
          "created_at" timestamptz NOT NULL,
          "updated_at" timestamptz NOT NULL,
          CONSTRAINT "task_$pk" PRIMARY KEY ("id")
        )\
        """)

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

      expected_statement =
        normalize_newlines("""
        CREATE TABLE "hologram_data"."task" (
          "id" uuid NOT NULL,
          "status" "hologram_data"."task_status_$enum" NOT NULL,
          CONSTRAINT "task_$pk" PRIMARY KEY ("id")
        )\
        """)

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

      expected_statement =
        normalize_newlines("""
        CREATE TABLE "hologram_data"."task_tags_$join" (
          "source_id" uuid NOT NULL,
          "target_id" uuid NOT NULL,
          CONSTRAINT "task_tags_$join_$pk" PRIMARY KEY ("source_id", "target_id")
        )\
        """)

      assert statements(op) == [expected_statement]
    end
  end

  describe "statements/1 for delete_role_grants" do
    test "renders the schema-qualified delete" do
      op = %{op: :delete_role_grants, table: "hologram_role_grant"}

      assert statements(op) == [~s(DELETE FROM "hologram_data"."hologram_role_grant")]
    end
  end

  describe "statements/1 for drop_column" do
    test "renders the column drop" do
      op = %{op: :drop_column, table: "task", column: "name"}

      assert statements(op) == [~s(ALTER TABLE "hologram_data"."task" DROP COLUMN "name")]
    end
  end

  describe "statements/1 for drop_enum_type" do
    test "renders the schema-qualified type drop" do
      op = %{op: :drop_enum_type, enum_type: "task_status_$enum"}

      assert statements(op) == [~s(DROP TYPE "hologram_data"."task_status_$enum")]
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

  describe "statements/1 for drop_index" do
    test "renders the schema-qualified index drop" do
      op = %{op: :drop_index, index: "task_project_id_$idx"}

      assert statements(op) == [~s(DROP INDEX "hologram_data"."task_project_id_$idx")]
    end
  end

  describe "statements/1 for drop_table" do
    test "renders a schema-qualified drop" do
      op = %{op: :drop_table, table: "task"}

      assert statements(op) == [~s(DROP TABLE "hologram_data"."task")]
    end
  end

  describe "statements/1 for rebuild_enum_type" do
    test "renders the rename-create-cast-drop sequence" do
      op = %{
        op: :rebuild_enum_type,
        enum_type: "task_status_$enum",
        values: ["todo", "done"],
        columns: [{"task", "status"}]
      }

      assert statements(op) == [
               ~s(ALTER TYPE "hologram_data"."task_status_$enum" ) <>
                 ~s(RENAME TO "task_status_$enum_$old"),
               ~s{CREATE TYPE "hologram_data"."task_status_$enum" AS ENUM ('todo', 'done')},
               ~s(ALTER TABLE "hologram_data"."task" ) <>
                 ~s(ALTER COLUMN "status" TYPE "hologram_data"."task_status_$enum" ) <>
                 ~s(USING "status"::text::"hologram_data"."task_status_$enum"),
               ~s(DROP TYPE "hologram_data"."task_status_$enum_$old")
             ]
    end

    test "renders one cast statement per column using the type" do
      op = %{
        op: :rebuild_enum_type,
        enum_type: "task_status_$enum",
        values: ["done"],
        columns: [{"project", "state"}, {"task", "status"}]
      }

      cast_statements =
        op
        |> statements()
        |> Enum.filter(&String.contains?(&1, "ALTER COLUMN"))

      assert length(cast_statements) == 2
      assert Enum.at(cast_statements, 0) =~ ~s(ALTER TABLE "hologram_data"."project")
      assert Enum.at(cast_statements, 1) =~ ~s(ALTER TABLE "hologram_data"."task")
    end

    test "renders an unscoped remap entry as a CASE expression in the cast" do
      op = %{
        op: :rebuild_enum_type,
        enum_type: "task_status_$enum",
        values: ["todo", "done"],
        columns: [{"task", "status"}],
        remap: [%{from: "wip", to: "todo", scope: nil}]
      }

      cast_statement =
        op
        |> statements()
        |> Enum.at(2)

      assert cast_statement ==
               ~s(ALTER TABLE "hologram_data"."task" ) <>
                 ~s(ALTER COLUMN "status" TYPE "hologram_data"."task_status_$enum" ) <>
                 ~s{USING (CASE WHEN "status"::text = 'wip' THEN 'todo' } <>
                 ~s{ELSE "status"::text END)::"hologram_data"."task_status_$enum"}
    end

    test "renders a scoped remap entry with its second column in the condition" do
      op = %{
        op: :rebuild_enum_type,
        enum_type: "hologram_role_grant_role_$enum",
        values: ["editor", "reviewer"],
        columns: [{"hologram_role_grant", "role"}],
        remap: [%{from: "editor", to: "reviewer", scope: {"resource_type", "MyApp.Task"}}]
      }

      cast_statement =
        op
        |> statements()
        |> Enum.at(2)

      assert cast_statement =~
               ~s{USING (CASE WHEN "role"::text = 'editor' } <>
                 ~s{AND "resource_type" = 'MyApp.Task' THEN 'reviewer' } <>
                 ~s{ELSE "role"::text END)}
    end

    test "renders a scoped remap entry before an unscoped one for the same value" do
      op = %{
        op: :rebuild_enum_type,
        enum_type: "hologram_role_grant_role_$enum",
        values: ["editor", "reviewer", "viewer"],
        columns: [{"hologram_role_grant", "role"}],
        remap: [
          %{from: "editor", to: "viewer", scope: nil},
          %{from: "editor", to: "reviewer", scope: {"resource_type", "MyApp.Task"}}
        ]
      }

      cast_statement =
        op
        |> statements()
        |> Enum.at(2)

      # First match wins in a searched CASE, so an unscoped branch rendered first would
      # swallow every row the scoped one singles out.
      {scoped_at, _length} = :binary.match(cast_statement, "'MyApp.Task'")
      {unscoped_at, _length} = :binary.match(cast_statement, "THEN 'viewer'")

      assert scoped_at < unscoped_at
    end

    test "shortens the temporary type name over the PostgreSQL identifier limit" do
      op = %{
        op: :rebuild_enum_type,
        enum_type: "task_extraordinarily_long_attribute_name_for_the_status_$enum",
        values: ["done"],
        columns: []
      }

      fitted_old_type = "task_extraordinarily_long_attribute_name_for_the_statu_aa768be9"
      [rename_statement, _create_statement, drop_statement] = statements(op)

      assert rename_statement =~ ~s(RENAME TO "#{fitted_old_type}")
      assert drop_statement == ~s(DROP TYPE "hologram_data"."#{fitted_old_type}")
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

  describe "statements/1 for widen_to_many" do
    test "renders the move of the reference values into the join table" do
      op = %{
        op: :widen_to_many,
        table: "task",
        join_table: "task_tags_$join",
        column: "tag_id"
      }

      assert statements(op) == [
               ~s{INSERT INTO "hologram_data"."task_tags_$join" ("source_id", "target_id") } <>
                 ~s{SELECT "id", "tag_id" FROM "hologram_data"."task" } <>
                 ~s{WHERE "tag_id" IS NOT NULL}
             ]
    end
  end

  describe "statements/1 for rename_column" do
    test "renders the column rename" do
      op = %{op: :rename_column, table: "task", from: "name", to: "title"}

      assert statements(op) == [
               ~s(ALTER TABLE "hologram_data"."task" RENAME COLUMN "name" TO "title")
             ]
    end
  end

  describe "statements/1 for rename_enum_type" do
    test "renders the type rename" do
      op = %{op: :rename_enum_type, from: "draft_status_$enum", to: "sketch_status_$enum"}

      assert statements(op) == [
               ~s(ALTER TYPE "hologram_data"."draft_status_$enum" ) <>
                 ~s(RENAME TO "sketch_status_$enum")
             ]
    end
  end

  describe "statements/1 for rename_enum_value" do
    test "renders the value rename" do
      op = %{
        op: :rename_enum_value,
        enum_type: "task_status_$enum",
        from: "done",
        to: "completed"
      }

      assert statements(op) == [
               ~s(ALTER TYPE "hologram_data"."task_status_$enum" ) <>
                 "RENAME VALUE 'done' TO 'completed'"
             ]
    end
  end

  describe "statements/1 for rename_index" do
    test "renders the index rename" do
      op = %{op: :rename_index, from: "draft_author_id_$idx", to: "sketch_author_id_$idx"}

      assert statements(op) == [
               ~s(ALTER INDEX "hologram_data"."draft_author_id_$idx" ) <>
                 ~s(RENAME TO "sketch_author_id_$idx")
             ]
    end
  end

  describe "statements/1 for rename_table" do
    test "renders the table rename" do
      op = %{op: :rename_table, from: "draft", to: "sketch"}

      assert statements(op) == [
               ~s(ALTER TABLE "hologram_data"."draft" RENAME TO "sketch")
             ]
    end
  end
end
