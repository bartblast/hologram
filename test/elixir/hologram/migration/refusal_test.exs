defmodule Hologram.Migration.RefusalTest do
  # The refusals, each against committed rows: a migration the existing data cannot follow
  # is refused before the DDL it cannot follow runs, and the database is left exactly as it
  # was.
  #
  # Four things are asserted for every one of them, because a refusal that raised while
  # leaving something behind would satisfy the first alone: the apply raises with the
  # message the operator is meant to act on, the version stays unapplied so the next deploy
  # retries the same file, the schema is what it was - a table, column or index the file
  # created, renamed or dropped before the refused op went back with it - and the rows are
  # byte-for-byte what they were.
  #
  # Only the scratch tier can make that last claim. Under the sandbox the rows a test wrote
  # and the rows a refusal spared live in the same never-committed transaction, so "the
  # data survived" is indistinguishable from "the whole test is about to be rolled back".
  #
  # Not here, and each for its own reason:
  #   * tightening a column while a row holds NULL - covered in full by the atomicity
  #     suite, whose "applies none of a file's ops when pre-flight refuses one of them" test
  #     uses that refusal as its lever and asserts the same three things.
  #   * a required attribute or to-one relationship ADDED without a value for the existing
  #     rows - refused EARLIER than the database, by `Model.fold/2` itself:
  #     `validate_filled_adds!/1` rejects an add that is required and carries neither
  #     backfill: nor, for an attribute, default:, exempting only entities the same file
  #     created before it. Its messages, which ask for backfill: or optional: true, are the
  #     ones a dev actually sees - covered by the model suite, and below for a relationship
  #     the same file renames, where only the compile error is asserted, since nothing
  #     reaches the database. A migration reaches the database-level check only around that
  #     validation: an optional add the same chunk tightens - an attribute whose default
  #     arrives after a rename, or a unique attribute or to-one, which declares none - tested
  #     below. An add whose computed backfill leaves rows nil is refused after its fill
  #     instead, which the backfill suite covers. Schema reconciliation folds a model from
  #     MODULES rather than ops, so a required attribute or to-one declared on a populated
  #     dev database reaches it there too, where the reconciler suite covers it.
  #   * a foreign key over orphaned rows - void by construction, since a relationship
  #     column is born together with its foreign key and no op adopts an existing column.
  #
  # async: false - every test of the tier opens raw sessions beside its scratch connection,
  # several in the contention suites, so the tier's modules run one at a time to keep the
  # server's connection count bounded.
  use Hologram.Test.ScratchDatabaseCase, async: false

  import Hologram.Migrator

  alias Hologram.DB.Connection
  alias Hologram.DB.Introspection
  alias Hologram.Entity.Model

  @context %{
    otp_app: "hologram",
    env: "test",
    hologram_version: "0.5.0",
    timestamp: ~U[2026-08-13 09:15:22.000000Z]
  }

  defp applied_versions_list do
    statement = ~s{SELECT "version" FROM "hologram_system"."migration" ORDER BY "version"}

    {:ok, %{rows: rows}} = Connection.query(statement)

    Enum.map(rows, fn [version] -> version end)
  end

  # A file adding an optional enum, and one making it required with a default that the same file
  # adds to the enum only below a rename, so the value isn't there yet when the column fills.
  defp grade_files(first_model) do
    add_grade =
      migration("20260813091523", [
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :grade,
          type: :enum,
          opts: [optional: true, values: [:a]],
          line: 3
        }
      ])

    tighten =
      migration("20260813091524", [
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :grade,
          changes: [optional: false, default: :fresh],
          line: 3
        },
        %{op: :rename_attribute, entity: MyApp.Task, from: :amount, to: :cost, line: 4},
        %{
          op: :add_enum_value,
          entity: MyApp.Task,
          attribute: :grade,
          value: :fresh,
          opts: [],
          line: 5
        }
      ])

    {add_grade, Model.fold(first_model, add_grade.ops), tighten}
  end

  # Separate from task_rows/0 because only the tests that add grade have the column.
  defp grade_rows do
    statement = """
    SELECT "title", "amount", "status"::text, "grade"::text
    FROM "hologram_data"."my_app_task"
    ORDER BY "title"
    """

    {:ok, %{rows: rows}} = Connection.query(statement)

    rows
  end

  defp insert_task(title, amount, status) do
    statement = """
    INSERT INTO "hologram_data"."my_app_task"
      ("id", "title", "amount", "status", "created_at", "server_created_at", "server_created_seq", "server_updated_at", "server_updated_seq", "updated_at", "$revisions")
    VALUES (gen_random_uuid(), $1, $2, $3, now(), now(), 0, now(), 0, now(), '{}')
    """

    {:ok, _result} = Connection.query(statement, [title, amount, status])
  end

  defp migration(version, ops) do
    %{version: version, path: "app/migrations/#{version}.ex", ops: ops}
  end

  defp task_rows do
    statement = """
    SELECT "title", "amount", "status"::text
    FROM "hologram_data"."my_app_task"
    ORDER BY "title"
    """

    {:ok, %{rows: rows}} = Connection.query(statement)

    rows
  end

  setup %{scratch: scratch} do
    create =
      migration("20260813091522", [
        %{op: :create_entity, entity: MyApp.Task, line: 3},
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :amount,
          type: :string,
          opts: [optional: true],
          line: 4
        },
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :status,
          type: :enum,
          opts: [values: [:done, :todo]],
          line: 5
        },
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :title,
          type: :string,
          opts: [],
          line: 6
        }
      ])

    first_model = Model.fold(Model.empty(), create.ops)

    route(scratch, fn ->
      :ok = run([create], first_model, @context)

      insert_task("one", "10", "done")
      insert_task("two", "not-a-number", "todo")
    end)

    [create: create, first_model: first_model]
  end

  describe "run/3" do
    test "refuses a type change the existing rows cannot follow", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      refused =
        migration("20260813142237", [
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :amount,
            changes: [type: :integer],
            line: 3
          }
        ])

      expected_msg =
        ~s(1 row in "my_app_task"."amount" cannot convert from text to int8 - ) <>
          "fix the data or remove the attribute and re-add it with the new type"

      assert_refused(scratch, create, first_model, refused, expected_msg)
    end

    # The third row shares an AMOUNT rather than a title, so the ordering task_rows/0
    # compares by stays total - two rows tying on it would make the before/after
    # comparison depend on an order the query does not fix.
    test "refuses a unique index over rows that repeat a value", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      route(scratch, fn -> insert_task("three", "10", "todo") end)

      refused =
        migration("20260813142237", [
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :amount,
            changes: [unique: true],
            line: 3
          }
        ])

      expected_msg =
        ~s{found 1 duplicate key in "my_app_task" over ("amount") - } <>
          "a unique index cannot be built while rows repeat a key - " <>
          "update the rows or drop the unique declaration"

      assert_refused(scratch, create, first_model, refused, expected_msg)
    end

    # The type change makes "10" and "010" one key, so only a check of the rows as the file
    # leaves them finds the repeat. The index meets Task's table before the rename moves it,
    # so it builds in the tail on my_app_job - the my_app_task the file creates afterwards is
    # a new, empty table that shares only the name.
    test "refuses a unique index over keys a type change in the same file makes repeat, under an entity name the file reuses",
         %{create: create, first_model: first_model, scratch: scratch} do
      route(scratch, fn ->
        statement =
          ~s{UPDATE "hologram_data"."my_app_task" SET "amount" = '010' WHERE "title" = 'two'}

        {:ok, _result} = Connection.query(statement)
      end)

      refused =
        migration("20260813142237", [
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :amount,
            changes: [type: :integer, unique: true],
            line: 3
          },
          %{op: :rename_entity, from: MyApp.Task, to: MyApp.Job, line: 6},
          %{op: :create_entity, entity: MyApp.Task, line: 8}
        ])

      expected_msg =
        ~s{found 1 duplicate key in "my_app_job" over ("amount") - } <>
          "a unique index cannot be built while rows repeat a key - " <>
          "update the rows or drop the unique declaration"

      assert_refused(scratch, create, first_model, refused, expected_msg)
    end

    # The column turns required in its first chunk, with no default to fill the rows - the
    # one declared after the rename fills nothing that predates it.
    test "refuses a required attribute whose default the same file declares only after a rename",
         %{create: create, first_model: first_model, scratch: scratch} do
      refused =
        migration("20260813142237", [
          %{
            op: :add_attribute,
            entity: MyApp.Task,
            name: :code,
            type: :integer,
            opts: [optional: true],
            line: 3
          },
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :code,
            changes: [optional: false],
            line: 4
          },
          %{op: :rename_attribute, entity: MyApp.Task, from: :title, to: :name, line: 5},
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :code,
            changes: [default: 5],
            line: 6
          }
        ])

      expected_msg =
        ~s(cannot add required column "code" to table "my_app_task" - ) <>
          "2 existing rows would have no value - " <>
          "add backfill: <value or expression> to the op making it required, " <>
          "declare default: <value>, keep the attribute optional: true, or clear the rows"

      assert_refused(scratch, create, first_model, refused, expected_msg)
    end

    # A to-one made required in its first chunk the same way, which declares no default, so it
    # isn't offered one.
    test "refuses a required to-one added optional and made required in its chunk", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      refused =
        migration("20260813142237", [
          %{op: :create_entity, entity: MyApp.User, line: 3},
          %{
            op: :add_relationship,
            entity: MyApp.Task,
            name: :author,
            type: MyApp.User,
            opts: [optional: true],
            line: 5
          },
          %{
            op: :change_relationship,
            entity: MyApp.Task,
            name: :author,
            changes: [optional: false],
            line: 7
          }
        ])

      expected_msg =
        ~s(cannot add required column "author_id" to table "my_app_task" - ) <>
          "2 existing rows would have no value - " <>
          "add backfill: <id or expression> to the op making it required, " <>
          "keep the relationship optional: true, or clear the rows"

      assert_refused(scratch, create, first_model, refused, expected_msg)
    end

    test "refuses a default its enum doesn't hold yet when a NULL needs it", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      {add_grade, grade_model, tighten} = grade_files(first_model)

      route(scratch, fn ->
        assert run([create, add_grade], grade_model, @context) == :ok

        rows_before = grade_rows()
        schema_before = Introspection.schema()
        full_model = Model.fold(grade_model, tighten.ops)

        expected_msg =
          ~s(the default "fresh" of column "grade" on table "my_app_task" is an enum value ) <>
            "its type doesn't hold yet when the column fills - move the change filling the " <>
            "column to the next migration file, under the names things have there"

        assert_error RuntimeError, expected_msg, fn ->
          run([create, add_grade, tighten], full_model, @context)
        end

        assert applied_versions_list() == ["20260813091522", "20260813091523"]
        assert Introspection.schema() == schema_before
        assert grade_rows() == rows_before
      end)
    end

    test "applies a default its enum doesn't hold yet when no NULL needs it", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      {add_grade, grade_model, tighten} = grade_files(first_model)

      route(scratch, fn ->
        assert run([create, add_grade], grade_model, @context) == :ok

        {:ok, _result} =
          Connection.query(~s|UPDATE "hologram_data"."my_app_task" SET "grade" = 'a'|)

        full_model = Model.fold(grade_model, tighten.ops)

        assert run([create, add_grade, tighten], full_model, @context) == :ok

        {:ok, %{rows: rows}} =
          Connection.query(
            ~s|SELECT "title", "grade"::text FROM "hologram_data"."my_app_task" ORDER BY "title"|
          )

        assert rows == [["one", "a"], ["two", "a"]]
        assert Introspection.schema().tables["my_app_task"].columns["grade"].null == false
      end)
    end

    # The column turns required in its own chunk, where it declares no default - the one
    # declared after the rename fills nothing that predates it.
    test "refuses tightening when the default arrives after a rename", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      route(scratch, fn -> insert_task("three", nil, "done") end)

      refused =
        migration("20260813142237", [
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :amount,
            changes: [optional: false],
            line: 3
          },
          %{op: :rename_attribute, entity: MyApp.Task, from: :title, to: :name, line: 4},
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :amount,
            changes: [default: "0"],
            line: 5
          }
        ])

      expected_msg =
        ~s(cannot make column "amount" on table "my_app_task" required - ) <>
          "found 1 row with NULL - add backfill: <value or expression> to the op, " <>
          "declare default: <value>, keep the attribute optional: true, or fix the data"

      assert_refused(scratch, create, first_model, refused, expected_msg)
    end

    # A unique attribute can't declare a default either, so it isn't offered one.
    test "refuses a required unique attribute added optional and made required in its chunk", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      refused =
        migration("20260813142237", [
          %{
            op: :add_attribute,
            entity: MyApp.Task,
            name: :serial,
            type: :integer,
            opts: [optional: true, unique: true],
            line: 3
          },
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :serial,
            changes: [optional: false],
            line: 4
          }
        ])

      expected_msg =
        ~s(cannot add required column "serial" to table "my_app_task" - ) <>
          "2 existing rows would have no value - " <>
          "add backfill: <value or expression> to the op making it required, " <>
          "keep the attribute optional: true, or clear the rows"

      assert_refused(scratch, create, first_model, refused, expected_msg)
    end

    # The op making the add required also gives it its type, and a backfill can't sit beside a
    # type change.
    test "refuses a required attribute added optional and given its type by the op making it required",
         %{create: create, first_model: first_model, scratch: scratch} do
      refused =
        migration("20260813142237", [
          %{
            op: :add_attribute,
            entity: MyApp.Task,
            name: :code,
            type: :string,
            opts: [optional: true],
            line: 3
          },
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :code,
            changes: [type: :integer, optional: false],
            line: 4
          }
        ])

      expected_msg =
        ~s(cannot add required column "code" to table "my_app_task" - ) <>
          "2 existing rows would have no value - " <>
          "change the type in an op of its own, then add backfill: <value or expression> to " <>
          "the op making it required, declare default: <value>, " <>
          "keep the attribute optional: true, or clear the rows"

      assert_refused(scratch, create, first_model, refused, expected_msg)
    end

    # A relationship declares no default, so it needs a backfill or optional: true - asked of the
    # add where it sits, under the name the rename takes away afterwards, and not satisfied by
    # the attribute that takes the name over and declares a default of its own.
    test "refuses a required relationship added before the same file renames it",
         %{first_model: first_model, scratch: scratch} do
      refused =
        migration("20260813142237", [
          %{op: :create_entity, entity: MyApp.User, line: 3},
          %{
            op: :add_relationship,
            entity: MyApp.Task,
            name: :author,
            type: MyApp.User,
            opts: [],
            line: 5
          },
          %{op: :rename_relationship, entity: MyApp.Task, from: :author, to: :creator, line: 7},
          %{
            op: :add_attribute,
            entity: MyApp.Task,
            name: :author_id,
            type: :integer,
            opts: [default: 5],
            line: 9
          }
        ])

      expected_msg =
        "required to-one relationships added without a value for existing rows - " <>
          ":author on MyApp.Task - declare backfill: <id> for a one-time value, or " <>
          "optional: true to leave them empty"

      route(scratch, fn ->
        assert_error Hologram.CompileError, expected_msg, fn ->
          Model.fold(first_model, refused.ops)
        end
      end)
    end

    # The third row repeats the first one's amount and status under a title of its own, so
    # only the key over both is repeated.
    test "refuses a key over rows that repeat it", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      route(scratch, fn -> insert_task("three", "10", "done") end)

      refused =
        migration("20260813142237", [
          %{op: :add_unique, entity: MyApp.Task, fields: [:amount, :status], line: 3}
        ])

      expected_msg =
        ~s{found 1 duplicate key in "my_app_task" over ("amount", "status") - } <>
          "a unique index cannot be built while rows repeat a key - " <>
          "update the rows or drop the unique declaration"

      assert_refused(scratch, create, first_model, refused, expected_msg)
    end

    # Asked right before the type change applies, against the indexes standing then: the
    # rename later in the file leaves the mapping the file ends with nothing to find the
    # index by.
    test "refuses a type change that makes rows repeat a unique value", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      unique =
        migration("20260813142237", [
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :amount,
            changes: [unique: true],
            line: 3
          }
        ])

      refused =
        migration("20260814101500", [
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :amount,
            changes: [type: :integer],
            line: 3
          },
          %{op: :rename_attribute, entity: MyApp.Task, from: :amount, to: :total, line: 4}
        ])

      unique_model = Model.fold(first_model, unique.ops)
      full_model = Model.fold(unique_model, refused.ops)

      expected_msg =
        ~s(cannot change column "amount" on table "my_app_task" from text to int8 - ) <>
          ~s{1 key over ("amount") would repeat once converted - } <>
          "fix the data, or drop the unique declaration before changing the type"

      route(scratch, fn ->
        {:ok, _result} =
          Connection.query(
            ~s(UPDATE "hologram_data"."my_app_task" SET "amount" = '010' WHERE "title" = 'two')
          )

        :ok = run([create, unique], unique_model, @context)

        rows_before = task_rows()

        assert_error RuntimeError, expected_msg, fn ->
          run([create, unique, refused], full_model, @context)
        end

        assert applied_versions_list() == ["20260813091522", "20260813142237"]
        assert task_rows() == rows_before
      end)
    end

    # The third row's NULL amount takes the default "10", which makes its key over amount and
    # status the first row's. Asked about the index as it stands where the fill runs - the
    # rename after it leaves the mapping the file ends with no index over amount.
    test "refuses filling a column made required when the default makes rows repeat a key", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      unique =
        migration("20260813142237", [
          %{op: :add_unique, entity: MyApp.Task, fields: [:amount, :status], line: 3}
        ])

      refused =
        migration("20260814101500", [
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :amount,
            changes: [optional: false, default: "10"],
            line: 3
          },
          %{op: :rename_attribute, entity: MyApp.Task, from: :amount, to: :cost, line: 4}
        ])

      unique_model = Model.fold(first_model, unique.ops)
      full_model = Model.fold(unique_model, refused.ops)

      expected_msg =
        ~s(cannot make column "amount" on table "my_app_task" required - ) <>
          ~s{filling its NULLs with the default would make 1 key repeat over ("amount", "status") - } <>
          "fix the data, keep the attribute optional: true, or drop the unique declaration"

      route(scratch, fn ->
        insert_task("three", nil, "done")

        :ok = run([create, unique], unique_model, @context)

        rows_before = task_rows()

        assert_error RuntimeError, expected_msg, fn ->
          run([create, unique, refused], full_model, @context)
        end

        assert applied_versions_list() == ["20260813091522", "20260813142237"]
        assert task_rows() == rows_before
      end)
    end

    test "refuses removing an enum value the existing rows still hold", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      refused =
        migration("20260813142237", [
          %{
            op: :delete_enum_value,
            entity: MyApp.Task,
            attribute: :status,
            value: :todo,
            line: 3
          }
        ])

      expected_msg =
        ~s(found 1 row in "my_app_task"."status" holding removed enum value 'todo' - ) <>
          "update the rows or re-add the value"

      assert_refused(scratch, create, first_model, refused, expected_msg)
    end

    test "refuses a type change to an attribute the same file renamed", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      refused =
        migration("20260813142237", [
          %{op: :rename_attribute, entity: MyApp.Task, from: :amount, to: :cost, line: 3},
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :cost,
            changes: [type: :integer],
            line: 4
          }
        ])

      expected_msg =
        ~s(1 row in "my_app_task"."cost" cannot convert from text to int8 - ) <>
          "fix the data or remove the attribute and re-add it with the new type"

      assert_refused(scratch, create, first_model, refused, expected_msg)
    end

    # The one refusal that raises without counting rows, so nothing but the check reading
    # the op stands between it and PostgreSQL's own cast error.
    test "refuses an unsupported type change to an attribute the same file renamed", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      refused =
        migration("20260813142237", [
          %{op: :rename_attribute, entity: MyApp.Task, from: :amount, to: :cost, line: 3},
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :cost,
            changes: [type: :boolean],
            line: 4
          }
        ])

      expected_msg =
        ~s(changing column "cost" on table "my_app_task" from text to boolean is not supported - ) <>
          "remove the attribute and re-add it with the new type"

      assert_refused(scratch, create, first_model, refused, expected_msg)
    end

    test "refuses a type change on an entity the same file renamed", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      refused =
        migration("20260813142237", [
          %{op: :rename_entity, from: MyApp.Task, to: MyApp.Job, line: 3},
          %{
            op: :change_attribute,
            entity: MyApp.Job,
            name: :amount,
            changes: [type: :integer],
            line: 4
          }
        ])

      expected_msg =
        ~s(1 row in "my_app_job"."amount" cannot convert from text to int8 - ) <>
          "fix the data or remove the attribute and re-add it with the new type"

      assert_refused(scratch, create, first_model, refused, expected_msg)
    end

    test "refuses removing an enum value from an attribute the same file renamed", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      refused =
        migration("20260813142237", [
          %{op: :rename_attribute, entity: MyApp.Task, from: :status, to: :state, line: 3},
          %{
            op: :delete_enum_value,
            entity: MyApp.Task,
            attribute: :state,
            value: :todo,
            line: 4
          }
        ])

      expected_msg =
        ~s(found 1 row in "my_app_task"."state" holding removed enum value 'todo' - ) <>
          "update the rows or re-add the value"

      assert_refused(scratch, create, first_model, refused, expected_msg)
    end
  end

  # The claims every refusal owes, asserted together so none can be made without the
  # others: it raises what the operator is meant to read, it applies nothing, it changes no
  # schema, and it moves no data. The schema goes before the rows, so a table left renamed
  # reports as a schema difference rather than a failed read.
  defp assert_refused(scratch, create, first_model, refused, expected_msg) do
    route(scratch, fn ->
      rows_before = task_rows()
      schema_before = Introspection.schema()
      full_model = Model.fold(first_model, refused.ops)

      assert_error RuntimeError, expected_msg, fn ->
        run([create, refused], full_model, @context)
      end

      assert applied_versions_list() == ["20260813091522"]
      assert Introspection.schema() == schema_before
      assert task_rows() == rows_before
    end)
  end
end
