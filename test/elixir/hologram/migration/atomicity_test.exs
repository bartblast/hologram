defmodule Hologram.Migration.AtomicityTest do
  # A file applies whole or not at all, through both of the gates that can stop it: the
  # pre-flight refusal, which runs over every op of the file before any of them executes,
  # and the transaction, which carries the ops that do execute together with the row
  # recording them.
  #
  # Only the scratch tier can ask the question at all. Under the sandbox every apply is
  # already inside a never-committed transaction, so "the file left nothing behind" is true
  # there whatever the migrator does - the rollback observed would be the one the sandbox
  # performs anyway. Here the applies commit, so what a failed file leaves behind is what
  # the next deploy would really find.
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

  # Passes the cast pre-flight, which tests the SYNTAX of a text value against int8's
  # input rules, and fails the cast itself, which also has a range. The one way a legal
  # migration reaches a database-level failure mid-file - see the plan's finding F-1.
  @out_of_range_amount "99999999999999999999"

  defp insert_task(title, amount) do
    statement = """
    INSERT INTO "hologram_data"."my_app_task" ("id", "title", "amount", "created_at", "updated_at")
    VALUES (gen_random_uuid(), $1, $2, now(), now())
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

    # One row that follows any change, and one that follows neither of the changes the
    # tests make: its NULL title blocks a tightening, its amount overflows int8.
    route(scratch, fn ->
      :ok = run([create], first_model, @context)

      insert_task("first", "10")
      insert_task(nil, @out_of_range_amount)
    end)

    [create: create, first_model: first_model]
  end

  describe "run/3" do
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
        assert task_columns() == ["amount", "created_at", "id", "title", "updated_at"]
        assert applied_versions() == MapSet.new(["20260813091522"])
        assert task_rows() == [["first", "10"], [nil, @out_of_range_amount]]
      end)
    end

    test "leaves nothing behind when a statement fails at the database", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      # A file the pre-flight passes and the database refuses: the cast check tests the
      # SYNTAX of a text value against int8's input rules, and int8 also has a range.
      failing =
        migration("20260813142237", [
          %{op: :rename_attribute, entity: MyApp.Task, from: :title, to: :name, line: 3},
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :amount,
            changes: [type: :integer],
            line: 4
          }
        ])

      full_model = Model.fold(first_model, failing.ops)

      # The file really does carry an op ahead of the one that fails - a rename renders
      # into a chunk of its own, ahead of the plain ops - so the apply reaches the failure
      # with work behind it rather than refusing at the first statement.
      render = Renderer.render(failing.ops, first_model)

      assert Enum.map(render.transactional, & &1.op) == [:rename_column, :alter_column]

      route(scratch, fn ->
        assert_raise MatchError, fn -> run([create, failing], full_model, @context) end

        # Nothing of the file stands, which is the whole of what a database outside the
        # transaction can be asked: an op applied and rolled back and an op that never ran
        # leave the same database behind, because uncommitted work is invisible to every
        # other session by construction. Verified rather than assumed - reversing the apply
        # order, so the cast fails before the rename runs, leaves this test green.
        assert task_columns() == ["amount", "created_at", "id", "title", "updated_at"]
        assert applied_versions() == MapSet.new(["20260813091522"])
        assert task_rows() == [["first", "10"], [nil, @out_of_range_amount]]
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
                 "amount",
                 "created_at",
                 "id",
                 "note",
                 "title",
                 "updated_at"
               ]

        assert applied_versions() == MapSet.new(["20260813091522", "20260813142237"])
        assert task_rows() == [["first", "10"], ["second", @out_of_range_amount]]
      end)
    end
  end
end
