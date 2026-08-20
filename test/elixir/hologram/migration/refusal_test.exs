defmodule Hologram.Migration.RefusalTest do
  # The refusals, each against committed rows: a migration the existing data cannot follow
  # is refused before any DDL runs, and the database is left exactly as it was.
  #
  # Three things are asserted for every one of them, because a refusal that raised while
  # leaving something behind would satisfy the first alone: the apply raises with the
  # message the operator is meant to act on, the version stays unapplied so the next deploy
  # retries the same file, and the rows are byte-for-byte what they were.
  #
  # Only the scratch tier can make that last claim. Under the sandbox the rows a test wrote
  # and the rows a refusal spared live in the same never-committed transaction, so "the
  # data survived" is indistinguishable from "the whole test is about to be rolled back".
  #
  # Not here, and each for its own reason:
  #   * tightening a column while a row holds NULL - covered in full by the atomicity
  #     suite, whose file-wide-gate test uses that refusal as its lever and asserts the
  #     same three things.
  #   * a required attribute the existing rows have no value for - refused EARLIER than
  #     the database, by `Model.fold/2` itself: `validate_filled_adds!/2` rejects an
  #     add_attribute that is required and carries neither backfill: nor default:, exempting
  #     only entities born in the same file. A migration therefore never reaches the
  #     database-level check, and its message ("declare backfill: for a one-time value...")
  #     is the one a dev actually sees - covered by the model suite. The database-level
  #     twin in Preflight is not dead code: schema reconciliation folds a model from
  #     MODULES rather than ops, so a required attribute declared on a populated dev
  #     database reaches it there, where the reconciler suite covers it.
  #   * a unique index meeting duplicate rows - no migration can produce it. The only
  #     unique index the model derives is the grant store's, born with its own empty table,
  #     so the check is reachable only by building the op by hand, which the sandboxed
  #     migrator suite already does. See the TODO there: it becomes a real migration when
  #     `unique: true` is declarable on an attribute (step 08 owns it).
  #   * a foreign key over orphaned rows - void by construction, since a relationship
  #     column is born together with its foreign key and no op adopts an existing column.
  #
  # async: false - every test of the tier opens raw sessions beside its scratch connection,
  # several in the contention suites, so the tier's modules run one at a time to keep the
  # server's connection count bounded.
  use Hologram.Test.ScratchDatabaseCase, async: false

  import Hologram.Migrator

  alias Hologram.DB.Connection
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

  defp insert_task(title, amount, status) do
    statement = """
    INSERT INTO "hologram_data"."my_app_task"
      ("id", "title", "amount", "status", "created_at", "updated_at")
    VALUES (gen_random_uuid(), $1, $2, $3, now(), now())
    """

    {:ok, _result} = Connection.query(statement, [title, amount, status])
  end

  defp migration(version, ops) do
    %{version: version, path: "#{version}.exs", ops: ops}
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
  end

  # The three claims every refusal owes, asserted together so none can be made without the
  # others: it raises what the operator is meant to read, it applies nothing, and it moves
  # no data.
  defp assert_refused(scratch, create, first_model, refused, expected_msg) do
    route(scratch, fn ->
      rows_before = task_rows()
      full_model = Model.fold(first_model, refused.ops)

      assert_error RuntimeError, expected_msg, fn ->
        run([create, refused], full_model, @context)
      end

      assert applied_versions_list() == ["20260813091522"]
      assert task_rows() == rows_before
    end)
  end
end
