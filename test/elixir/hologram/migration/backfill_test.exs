defmodule Hologram.Migration.BackfillTest do
  # What `backfill:` reaches and what it does not. It is a one-time fill of the rows that
  # predate a column, run between adding the column nullable and tightening it - never a
  # rule the column keeps. No DEFAULT clause is emitted for it, or for a declared
  # `default:` either: at the database level a required column is NOT NULL and nothing
  # more, and supplying a value for a new row is the app's business.
  #
  # The scratch tier is what makes the question askable. Under the sandbox every row a test
  # writes lives in the same never-committed transaction as the apply that is supposed to
  # find them "already there", so a fill of pre-existing rows cannot be told from a fill of
  # the test's own uncommitted ones.
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

  defp insert_task(title) do
    statement = """
    INSERT INTO "hologram_data"."my_app_task" ("id", "title", "created_at", "updated_at")
    VALUES (gen_random_uuid(), $1, now(), now())
    """

    {:ok, _result} = Connection.query(statement, [title])
  end

  defp insert_task(title, priority) do
    statement = """
    INSERT INTO "hologram_data"."my_app_task"
      ("id", "title", "priority", "created_at", "updated_at")
    VALUES (gen_random_uuid(), $1, $2, now(), now())
    """

    Connection.query(statement, [title, priority])
  end

  defp migration(version, ops) do
    %{version: version, path: "#{version}.exs", ops: ops}
  end

  # What the column itself carries afterwards: whether it is required, and whether the
  # database holds a default for it.
  defp priority_column do
    statement = """
    SELECT a.attnotnull, pg_catalog.pg_get_expr(d.adbin, d.adrelid)
    FROM pg_catalog.pg_attribute a
    JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
    WHERE n.nspname = 'hologram_data' AND c.relname = 'my_app_task'
      AND a.attname = 'priority'
    """

    {:ok, %{rows: [[not_null, default]]}} = Connection.query(statement)

    %{default: default, not_null: not_null}
  end

  defp task_rows do
    statement = """
    SELECT "title", "priority" FROM "hologram_data"."my_app_task" ORDER BY "title"
    """

    {:ok, %{rows: rows}} = Connection.query(statement)

    rows
  end

  setup do
    create =
      migration("20260813091522", [
        %{op: :create_entity, entity: MyApp.Task, line: 3},
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :title,
          type: :string,
          opts: [],
          line: 4
        }
      ])

    backfilled =
      migration("20260813142237", [
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :priority,
          type: :integer,
          opts: [backfill: 7],
          line: 3
        }
      ])

    first_model = Model.fold(Model.empty(), create.ops)
    full_model = Model.fold(first_model, backfilled.ops)

    [chain: [create, backfilled], first_model: first_model, full_model: full_model]
  end

  describe "run/3" do
    test "fills every row that predates the column", %{
      chain: chain,
      first_model: first_model,
      full_model: full_model,
      scratch: scratch
    } do
      route(scratch, fn ->
        assert run([hd(chain)], first_model, @context) == :ok

        insert_task("one")
        insert_task("three")
        insert_task("two")

        assert run(chain, full_model, @context) == :ok

        assert task_rows() == [["one", 7], ["three", 7], ["two", 7]]
      end)
    end

    test "leaves no default behind for the rows that come after", %{
      chain: chain,
      first_model: first_model,
      full_model: full_model,
      scratch: scratch
    } do
      route(scratch, fn ->
        assert run([hd(chain)], first_model, @context) == :ok

        insert_task("one")

        assert run(chain, full_model, @context) == :ok

        # The fill ran once, as a statement. The column is left required and bare - a
        # DEFAULT would have made the backfill a standing rule for every later row.
        assert priority_column() == %{default: nil, not_null: true}

        # A row arriving with its own value keeps it, rather than being backfilled again.
        assert {:ok, _result} = insert_task("two", 99)

        # And a row arriving with none is refused by the database, because the value for a
        # new row is the app's to supply - the migration spoke only for the rows it found.
        assert {:error, %Postgrex.Error{postgres: %{code: :not_null_violation}}} =
                 insert_task("three", nil)

        assert task_rows() == [["one", 7], ["two", 99]]
      end)
    end
  end
end
