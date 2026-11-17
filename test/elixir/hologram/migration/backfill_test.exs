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
  alias Hologram.DB.SortKey
  alias Hologram.Entity.Model

  @context %{
    otp_app: "hologram",
    env: "test",
    hologram_version: "0.5.0",
    timestamp: ~U[2026-08-13 09:15:22.000000Z]
  }

  # A string attribute arriving on a populated table: its sort and search key companions
  # are computed from the value the backfill gives the existing rows. Past 64 bytes, so the
  # search key is a value rather than NULL.
  @note String.duplicate("Zed ", 20)

  @add_note %{
    op: :add_attribute,
    entity: MyApp.Task,
    name: :note,
    type: :string,
    opts: [optional: true, backfill: @note],
    line: 3
  }

  defp insert_task(title) do
    statement = """
    INSERT INTO "hologram_data"."my_app_task" ("id", "title", "created_at", "updated_at", "$revisions")
    VALUES (gen_random_uuid(), $1, now(), now(), '{}')
    """

    {:ok, _result} = Connection.query(statement, [title])
  end

  defp insert_task(title, priority) do
    statement = """
    INSERT INTO "hologram_data"."my_app_task"
      ("id", "title", "priority", "created_at", "updated_at", "$revisions")
    VALUES (gen_random_uuid(), $1, $2, now(), now(), '{}')
    """

    Connection.query(statement, [title, priority])
  end

  defp migration(version, ops) do
    %{version: version, path: "app/migrations/#{version}.ex", ops: ops}
  end

  # What the column itself carries afterwards: whether it is required, and whether the
  # database holds a default for it.
  defp column_flags(table, column) do
    statement = """
    SELECT a.attnotnull, pg_catalog.pg_get_expr(d.adbin, d.adrelid)
    FROM pg_catalog.pg_attribute a
    JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
    WHERE n.nspname = 'hologram_data' AND c.relname = $1 AND a.attname = $2
    """

    {:ok, %{rows: [[not_null, default]]}} = Connection.query(statement, [table, column])

    %{default: default, not_null: not_null}
  end

  defp rows_of(table, columns) do
    select_list = Enum.map_join(columns, ", ", &~s("#{&1}"))

    statement =
      ~s(SELECT #{select_list} FROM "hologram_data"."#{table}" ORDER BY "title")

    {:ok, %{rows: rows}} = Connection.query(statement)

    rows
  end

  defp status_migrations do
    add_status =
      migration("20260813142237", [
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :status,
          type: :enum,
          opts: [values: [:done, :todo], optional: true],
          line: 3
        }
      ])

    tighten =
      migration("20260813150000", [
        %{
          op: :add_enum_value,
          entity: MyApp.Task,
          attribute: :status,
          value: :unknown,
          opts: [after: :todo],
          line: 3
        },
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :status,
          changes: [optional: false, default: :unknown],
          line: 4
        }
      ])

    {add_status, tighten}
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
        assert column_flags("my_app_task", "priority") == %{default: nil, not_null: true}

        # A row arriving with its own value keeps it, rather than being backfilled again.
        assert {:ok, _result} = insert_task("two", 99)

        # And a row arriving with none is refused by the database, because the value for a
        # new row is the app's to supply - the migration spoke only for the rows it found.
        assert {:error, %Postgrex.Error{postgres: %{code: :not_null_violation}}} =
                 insert_task("three", nil)

        assert task_rows() == [["one", 7], ["two", 99]]
      end)
    end

    # The companions fill after every op of the file has run, so they are found under the
    # name the rename gives the attribute - under the one it was added with, nothing stands.
    test "fills the companions of an attribute the same file renames", %{
      chain: [create | _rest],
      first_model: first_model,
      scratch: scratch
    } do
      rename_op = %{op: :rename_attribute, entity: MyApp.Task, from: :note, to: :remark, line: 4}
      renamed = migration("20260813142237", [@add_note, rename_op])

      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        insert_task("one")

        assert run([create, renamed], Model.fold(first_model, renamed.ops), @context) == :ok

        assert rows_of("my_app_task", ["remark", "remark_$sort", "remark_$search"]) == [
                 [@note, SortKey.compute(@note), SortKey.search_key(@note)]
               ]
      end)
    end

    test "fills the companions of an attribute whose entity the same file renames", %{
      chain: [create | _rest],
      first_model: first_model,
      scratch: scratch
    } do
      rename_op = %{op: :rename_entity, from: MyApp.Task, to: MyApp.Job, line: 4}
      renamed = migration("20260813142237", [@add_note, rename_op])

      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        insert_task("one")

        assert run([create, renamed], Model.fold(first_model, renamed.ops), @context) == :ok

        assert rows_of("my_app_job", ["note", "note_$sort", "note_$search"]) == [
                 [@note, SortKey.compute(@note), SortKey.search_key(@note)]
               ]
      end)
    end

    test "fills a required attribute's declared default before the same file renames it", %{
      chain: [create | _rest],
      first_model: first_model,
      scratch: scratch
    } do
      renamed =
        migration("20260813142237", [
          %{
            op: :add_attribute,
            entity: MyApp.Task,
            name: :code,
            type: :integer,
            opts: [default: 5],
            line: 3
          },
          %{op: :rename_attribute, entity: MyApp.Task, from: :code, to: :num, line: 4}
        ])

      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        insert_task("one")
        insert_task("two")

        assert run([create, renamed], Model.fold(first_model, renamed.ops), @context) == :ok

        assert rows_of("my_app_task", ["title", "num"]) == [["one", 5], ["two", 5]]
      end)
    end

    # The NULLs take the declared default before the column tightens over them, as schema
    # reconciliation fills them in dev.
    test "fills the NULLs of a column turning required with its declared default", %{
      chain: [create | _rest],
      first_model: first_model,
      scratch: scratch
    } do
      add_amount =
        migration("20260813142237", [
          %{
            op: :add_attribute,
            entity: MyApp.Task,
            name: :amount,
            type: :string,
            opts: [optional: true],
            line: 3
          }
        ])

      tighten =
        migration("20260813150000", [
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :amount,
            changes: [optional: false, default: @note],
            line: 3
          }
        ])

      added_model = Model.fold(first_model, add_amount.ops)

      route(scratch, fn ->
        assert run([create, add_amount], added_model, @context) == :ok

        insert_task("one")
        insert_task("two")

        # Written past the app, so its companions stay NULL - a fill reaching beyond the
        # NULL rows would show here.
        {:ok, _result} =
          Connection.query(
            ~s(UPDATE "hologram_data"."my_app_task" SET "amount" = 'kept' WHERE "title" = 'two')
          )

        chain = [create, add_amount, tighten]

        assert run(chain, Model.fold(added_model, tighten.ops), @context) == :ok

        assert rows_of("my_app_task", ["title", "amount", "amount_$sort", "amount_$search"]) ==
                 [
                   ["one", @note, SortKey.compute(@note), SortKey.search_key(@note)],
                   ["two", "kept", nil, nil]
                 ]

        assert column_flags("my_app_task", "amount").not_null
      end)
    end

    test "fills the NULLs of a column turning required with the default its add declared before a rename",
         %{chain: [create | _rest], first_model: first_model, scratch: scratch} do
      tighten =
        migration("20260813142237", [
          %{
            op: :add_attribute,
            entity: MyApp.Task,
            name: :code,
            type: :integer,
            opts: [optional: true, default: 5],
            line: 3
          },
          %{op: :rename_attribute, entity: MyApp.Task, from: :code, to: :num, line: 4},
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :num,
            changes: [optional: false],
            line: 5
          }
        ])

      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        insert_task("one")

        assert run([create, tighten], Model.fold(first_model, tighten.ops), @context) == :ok

        assert rows_of("my_app_task", ["title", "num"]) == [["one", 5]]
        assert column_flags("my_app_task", "num").not_null
      end)
    end

    # PostgreSQL refuses a value ALTER TYPE added in the same transaction, even as the
    # parameter of an UPDATE that matches no row - so a tightening with nothing to fill runs
    # no fill at all.
    test "makes a column required with a default the same file adds to its enum, on an empty table",
         %{chain: [create | _rest], first_model: first_model, scratch: scratch} do
      {add_status, tighten} = status_migrations()
      added_model = Model.fold(first_model, add_status.ops)

      route(scratch, fn ->
        chain = [create, add_status, tighten]

        assert run(chain, Model.fold(added_model, tighten.ops), @context) == :ok

        assert column_flags("my_app_task", "status").not_null
      end)
    end

    test "makes a column required with a default the same file adds to its enum, over rows with no NULL",
         %{chain: [create | _rest], first_model: first_model, scratch: scratch} do
      {add_status, tighten} = status_migrations()
      added_model = Model.fold(first_model, add_status.ops)

      route(scratch, fn ->
        assert run([create, add_status], added_model, @context) == :ok

        insert_task("one")

        {:ok, _result} =
          Connection.query(~s(UPDATE "hologram_data"."my_app_task" SET "status" = 'done'))

        chain = [create, add_status, tighten]

        assert run(chain, Model.fold(added_model, tighten.ops), @context) == :ok

        assert rows_of("my_app_task", ["title", "status"]) == [["one", "done"]]
        assert column_flags("my_app_task", "status").not_null
      end)
    end

    test "fills the NULLs of an enum column turning required with its declared default", %{
      chain: [create | _rest],
      first_model: first_model,
      scratch: scratch
    } do
      {add_status, _tighten} = status_migrations()
      added_model = Model.fold(first_model, add_status.ops)

      tighten =
        migration("20260813150000", [
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :status,
            changes: [optional: false, default: :todo],
            line: 3
          }
        ])

      route(scratch, fn ->
        assert run([create, add_status], added_model, @context) == :ok

        insert_task("one")

        chain = [create, add_status, tighten]

        assert run(chain, Model.fold(added_model, tighten.ops), @context) == :ok

        assert rows_of("my_app_task", ["title", "status"]) == [["one", "todo"]]
      end)
    end
  end
end
