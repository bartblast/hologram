defmodule Hologram.Migration.AtomicityTest do
  # A file applies whole or not at all. The gate that enforces it is the pre-flight refusal,
  # which runs over every op of the file before any of them executes - so a file with one
  # bad op does not apply its good ones first.
  #
  # The transaction underneath is the second gate, and it has no reachable trigger: every
  # op the migration DSL can express is pre-flight checked, and the checks are total in the
  # direction that matters - each refuses at least every row PostgreSQL would. A file that
  # gets past pre-flight and then fails mid-apply is by construction a Hologram bug, not a
  # scenario, so it is recorded here rather than tested. It WAS testable until the cast
  # checks gained their range branches: an out-of-range numeric used to pass the syntax-only
  # check and fail the cast, which is the state this suite reproduced before that was fixed.
  #
  # The pre-flight has TWO moments, and they take back different amounts of work. The
  # transactional one runs before any op executes, so a file it refuses never ran anything.
  # The TAIL's runs after the transactional ops have applied - an index build cannot go
  # inside the file's transaction, so its check is the last thing before the commit - and a
  # file refused there is one whose work was really done and really taken back.
  #
  # Only the scratch tier can ask the question at all. Under the sandbox every apply is
  # already inside a never-committed transaction, so "the file left nothing behind" is true
  # there whatever the migrator does. Here the applies commit, so what a refused file leaves
  # behind is what the next deploy would really find.
  #
  # async: false - every test of the tier opens raw sessions beside its scratch connection,
  # several in the contention suites, so the tier's modules run one at a time to keep the
  # server's connection count bounded.
  use Hologram.Test.ScratchDatabaseCase, async: false

  import Hologram.Migrator

  alias Hologram.DB.Connection
  alias Hologram.Entity.Model
  alias Hologram.Migration.Renderer

  @context %{
    otp_app: "hologram",
    env: "test",
    hologram_version: "0.5.0",
    timestamp: ~U[2026-08-13 09:15:22.000000Z]
  }

  defp insert_task(title, amount) do
    statement = """
    INSERT INTO "hologram_data"."my_app_task" ("id", "title", "amount", "created_at", "updated_at", "$revisions")
    VALUES (gen_random_uuid(), $1, $2, now(), now(), '{}')
    """

    {:ok, _result} = Connection.query(statement, [title, amount])
  end

  defp migration(version, ops) do
    %{version: version, path: "#{version}.exs", ops: ops}
  end

  defp task_columns do
    statement = """
    SELECT a.attname
    FROM pg_catalog.pg_attribute a
    JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'hologram_data' AND c.relname = 'my_app_task'
      AND a.attnum > 0 AND NOT a.attisdropped
    ORDER BY a.attname
    """

    {:ok, %{rows: rows}} = Connection.query(statement)

    Enum.map(rows, fn [name] -> name end)
  end

  defp task_rows do
    statement = """
    SELECT "title", "amount" FROM "hologram_data"."my_app_task" ORDER BY "amount"
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
          name: :title,
          type: :string,
          opts: [optional: true],
          line: 5
        }
      ])

    first_model = Model.fold(Model.empty(), create.ops)

    # One row that follows the change the tests make, and one that blocks it with a NULL.
    route(scratch, fn ->
      :ok = run([create], first_model, @context)

      insert_task("first", "10")
      insert_task(nil, "20")
    end)

    [create: create, first_model: first_model]
  end

  describe "run/3" do
    # The other refusal point. Here the file's transactional op APPLIES and is then taken
    # back, where the test below refuses before anything runs at all - which is why this one
    # asserts the render's shape too: without it, "the rename is gone" would be satisfied by
    # a file that never carried a rename to begin with. What no assertion from outside can
    # separate is applied-then-rolled-back from never-applied, since an uncommitted change is
    # invisible to every other session by construction. The ORDER is what settles it, and it
    # is fixed in apply_transactional/3: transactional ops execute, then the tail is checked.
    test "applies none of a file whose tail check refuses after its transactional ops ran", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      route(scratch, fn -> insert_task("first", "30") end)

      refused =
        migration("20260813142237", [
          %{op: :rename_attribute, entity: MyApp.Task, from: :amount, to: :total, line: 3},
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :title,
            changes: [unique: true],
            line: 4
          }
        ])

      full_model = Model.fold(first_model, refused.ops)
      render = Renderer.render(refused.ops, first_model)

      assert render.transactional != []
      assert [%{op: :create_index, unique: true}] = render.tail

      route(scratch, fn ->
        expected_msg =
          ~s{found 1 duplicate key in "my_app_task" over ("title") - } <>
            "a unique index cannot be built while rows repeat a key - " <>
            "update the rows or drop the unique declaration"

        assert_error RuntimeError, expected_msg, fn ->
          run([create, refused], full_model, @context)
        end

        # The rename applied inside the transaction the refusal then rolled back: the column
        # answers to its old name, and nothing of the file stands.
        assert task_columns() == [
                 "$revisions",
                 "amount",
                 "amount_$sort",
                 "created_at",
                 "id",
                 "title",
                 "title_$sort",
                 "updated_at"
               ]

        assert applied_versions() == MapSet.new(["20260813091522"])
        assert task_rows() == [["first", "10"], [nil, "20"], ["first", "30"]]
      end)
    end

    test "applies none of a file's ops when pre-flight refuses one of them", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      refused =
        migration("20260813142237", [
          %{
            op: :add_attribute,
            entity: MyApp.Task,
            name: :note,
            type: :string,
            opts: [optional: true],
            line: 3
          },
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :title,
            changes: [optional: false],
            line: 4
          }
        ])

      full_model = Model.fold(first_model, refused.ops)

      route(scratch, fn ->
        expected_msg =
          ~s(cannot make column "title" on table "my_app_task" required - ) <>
            "found 1 row with NULL - declare default: <value>, " <>
            "keep the attribute optional: true, or fix the data"

        assert_error RuntimeError, expected_msg, fn ->
          run([create, refused], full_model, @context)
        end

        # The op that would have succeeded never ran: the refusal covers the file, not the
        # op that earned it.
        assert task_columns() == [
                 "$revisions",
                 "amount",
                 "amount_$sort",
                 "created_at",
                 "id",
                 "title",
                 "title_$sort",
                 "updated_at"
               ]

        assert applied_versions() == MapSet.new(["20260813091522"])
        assert task_rows() == [["first", "10"], [nil, "20"]]
      end)
    end

    test "applies the refused file once the data it refused over is fixed", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      refused =
        migration("20260813142237", [
          %{
            op: :add_attribute,
            entity: MyApp.Task,
            name: :note,
            type: :string,
            opts: [optional: true],
            line: 3
          },
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :title,
            changes: [optional: false],
            line: 4
          }
        ])

      full_model = Model.fold(first_model, refused.ops)

      route(scratch, fn ->
        assert_raise RuntimeError, fn -> run([create, refused], full_model, @context) end

        # The way out the message names: give the row a value, then deploy again.
        fill_title = ~s{UPDATE "hologram_data"."my_app_task" SET "title" = 'second' }
        {:ok, _result} = Connection.query(fill_title <> ~s{WHERE "title" IS NULL})

        assert run([create, refused], full_model, @context) == :ok

        assert task_columns() == [
                 "$revisions",
                 "amount",
                 "amount_$sort",
                 "created_at",
                 "id",
                 "note",
                 "note_$sort",
                 "title",
                 "title_$sort",
                 "updated_at"
               ]

        assert applied_versions() == MapSet.new(["20260813091522", "20260813142237"])
        assert task_rows() == [["first", "10"], ["second", "20"]]
      end)
    end
  end
end
