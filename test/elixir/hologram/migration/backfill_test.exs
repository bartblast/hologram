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
  alias Hologram.Migration.Value

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
    INSERT INTO "hologram_data"."my_app_task" ("id", "title", "created_at", "server_created_at", "server_updated_at", "updated_at", "$revisions")
    VALUES (gen_random_uuid(), $1, now(), now(), now(), now(), '{}')
    """

    {:ok, _result} = Connection.query(statement, [title])
  end

  defp insert_task(title, priority) do
    statement = """
    INSERT INTO "hologram_data"."my_app_task"
      ("id", "title", "priority", "created_at", "server_created_at", "server_updated_at", "updated_at", "$revisions")
    VALUES (gen_random_uuid(), $1, $2, now(), now(), now(), now(), '{}')
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

  defp has_column?(table, column) do
    {:ok, %{rows: [[count]]}} =
      Connection.query(
        "SELECT COUNT(*) FROM information_schema.columns " <>
          "WHERE table_schema = 'hologram_data' AND table_name = $1 AND column_name = $2",
        [table, column]
      )

    count == 1
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

    # The key holds the title too, so the filled rows take one amount and still repeat no key.
    test "fills the NULLs of a column under a key the fill makes no rows repeat", %{
      chain: [create | _rest],
      first_model: first_model,
      scratch: scratch
    } do
      keyed =
        migration("20260813142237", [
          %{
            op: :add_attribute,
            entity: MyApp.Task,
            name: :amount,
            type: :string,
            opts: [optional: true],
            line: 3
          },
          %{op: :add_unique, entity: MyApp.Task, fields: [:title, :amount], line: 4}
        ])

      tighten =
        migration("20260813150000", [
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :amount,
            changes: [optional: false, default: "0"],
            line: 3
          }
        ])

      keyed_model = Model.fold(first_model, keyed.ops)

      route(scratch, fn ->
        assert run([create, keyed], keyed_model, @context) == :ok

        insert_task("one")
        insert_task("two")

        chain = [create, keyed, tighten]

        assert run(chain, Model.fold(keyed_model, tighten.ops), @context) == :ok

        assert rows_of("my_app_task", ["title", "amount"]) == [["one", "0"], ["two", "0"]]
      end)
    end
  end

  describe "run/3, a computed backfill on an added attribute" do
    setup %{chain: [create | _rest], first_model: first_model} do
      [create: create, first_model: first_model]
    end

    defp computed_add(name, type, term, opts) do
      %{
        op: :add_attribute,
        entity: MyApp.Task,
        name: name,
        type: type,
        opts: Keyword.put(opts, :backfill, %Value{term: term}),
        line: 3
      }
    end

    defp apply_file(ops, create, first_model) do
      file = migration("20260813142237", ops)

      run([create, file], Model.fold(first_model, file.ops), @context)
    end

    test "fills a computed string and its sort key", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        insert_task("Ann")
        insert_task("Bob")

        term = {:concat, [{:name, [:title]}, {:value, "!"}]}

        assert apply_file(
                 [computed_add(:shout, :string, term, optional: true)],
                 create,
                 first_model
               ) ==
                 :ok

        assert rows_of("my_app_task", ["title", "shout", "shout_$sort"]) == [
                 ["Ann", "Ann!", SortKey.compute("Ann!")],
                 ["Bob", "Bob!", SortKey.compute("Bob!")]
               ]
      end)
    end

    test "fills a computed integer", %{create: create, first_model: first_model, scratch: scratch} do
      add_priority = %{
        op: :add_attribute,
        entity: MyApp.Task,
        name: :priority,
        type: :integer,
        opts: [optional: true],
        line: 2
      }

      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        insert_task("one")

        ops = [
          add_priority,
          computed_add(:copy, :integer, {:coalesce, [{:name, [:priority]}, {:value, 9}]},
            optional: true
          )
        ]

        assert apply_file(ops, create, first_model) == :ok
        assert rows_of("my_app_task", ["title", "copy"]) == [["one", 9]]
      end)
    end

    test "refuses a required attribute the expression leaves nil, schema unchanged", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      term = {:at, {:split, {:name, [:title]}, {:value, ", "}}, {:value, 1}}

      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        insert_task("Porto")
        insert_task("Lyon")
        insert_task("Paris, France")

        assert_error RuntimeError,
                     ~s(the backfill of column "country" on table "my_app_task" leaves 2 rows ) <>
                       "without a value - give the expression a value for them, like " <>
                       "coalesce(..., <value>), or make the attribute optional: true",
                     fn ->
                       apply_file(
                         [computed_add(:country, :string, term, [])],
                         create,
                         first_model
                       )
                     end

        refute has_column?("my_app_task", "country")
      end)
    end

    test "leaves an optional attribute nil where the expression gives none", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      term = {:at, {:split, {:name, [:title]}, {:value, ", "}}, {:value, 1}}

      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        insert_task("Paris, France")
        insert_task("Porto")

        assert apply_file(
                 [computed_add(:country, :string, term, optional: true)],
                 create,
                 first_model
               ) == :ok

        assert rows_of("my_app_task", ["title", "country"]) == [
                 ["Paris, France", "France"],
                 ["Porto", nil]
               ]
      end)
    end

    test "applies computed adds in a row, each reading the one before it", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      ops =
        for {name, source} <- [a: :title, b: :a, c: :b, d: :c, e: :d] do
          computed_add(name, :string, {:name, [source]}, optional: true)
        end

      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        insert_task("one")

        assert apply_file(ops, create, first_model) == :ok

        assert rows_of("my_app_task", ["a", "b", "c", "d", "e"]) ==
                 [["one", "one", "one", "one", "one"]]
      end)
    end

    test "doesn't let a declared default fill what the expression left nil", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      term = {:at, {:split, {:name, [:title]}, {:value, ", "}}, {:value, 1}}

      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        insert_task("Porto")

        assert_error RuntimeError, ~r/leaves 1 row without a value/, fn ->
          apply_file(
            [computed_add(:country, :string, term, default: "Unknown")],
            create,
            first_model
          )
        end
      end)
    end

    # "B" sorts before "a" by bytes and after it by sort key, so the tie below is decided by the key
    # the file's own fill has to have written by then.
    test "orders a most_common by a sort key the same file filled", %{scratch: scratch} do
      create =
        migration("20260813091522", [
          %{op: :create_entity, entity: MyApp.Tag, line: 2},
          %{
            op: :add_attribute,
            entity: MyApp.Tag,
            name: :raw,
            type: :string,
            opts: [],
            line: 2
          },
          %{op: :create_entity, entity: MyApp.Task, line: 3},
          %{
            op: :add_attribute,
            entity: MyApp.Task,
            name: :title,
            type: :string,
            opts: [],
            line: 4
          },
          %{
            op: :add_relationship,
            entity: MyApp.Task,
            name: :tags,
            type: [MyApp.Tag],
            opts: [],
            line: 5
          }
        ])

      first_model = Model.fold(Model.empty(), create.ops)

      file =
        migration("20260813142237", [
          %{
            op: :add_attribute,
            entity: MyApp.Tag,
            name: :label,
            type: :string,
            opts: [optional: true, backfill: %Value{term: {:name, [:raw]}}],
            line: 2
          },
          computed_add(
            :top,
            :string,
            {:most_common, {:relationship, [:tags]}, :label},
            optional: true
          ),
          %{op: :rename_attribute, entity: MyApp.Tag, from: :label, to: :name, line: 4}
        ])

      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        insert_task("one")

        {:ok, %{rows: [[task_id]]}} =
          Connection.query(~s(SELECT "id" FROM "hologram_data"."my_app_task"))

        for raw <- ["B", "a"] do
          {:ok, %{rows: [[tag_id]]}} =
            Connection.query(
              ~s|INSERT INTO "hologram_data"."my_app_tag" ("id", "raw", "raw_$sort", | <>
                ~s|"created_at", "server_created_at", "server_updated_at", "updated_at", | <>
                ~s|"$revisions") VALUES (gen_random_uuid(), $1, $2, now(), now(), now(), now(), | <>
                ~s|'{}') RETURNING "id"|,
              [raw, SortKey.compute(raw)]
            )

          {:ok, _result} =
            Connection.query(
              ~s|INSERT INTO "hologram_data"."my_app_task_tags_$join" | <>
                ~s|("source_id", "target_id") VALUES ($1, $2)|,
              [task_id, tag_id]
            )
        end

        assert run([create, file], Model.fold(first_model, file.ops), @context) == :ok
        assert rows_of("my_app_task", ["title", "top"]) == [["one", "a"]]
      end)
    end
  end

  describe "run/3, a computed fill breaking its member's declared rules" do
    setup %{chain: [create | _rest], first_model: first_model} do
      [create: create, first_model: first_model]
    end

    defp assert_fill_refused(context, titles, ops, message) do
      %{create: create, first_model: first_model, scratch: scratch} = context

      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        Enum.each(titles, &insert_task/1)

        assert_error RuntimeError, message, fn -> apply_file(ops, create, first_model) end

        refute has_column?("my_app_task", "copy")
      end)
    end

    test "refuses a value over max_length", context do
      op = computed_add(:copy, :string, {:name, [:title]}, optional: true, max_length: 2)

      assert_fill_refused(
        context,
        ["ab", "long", "longer"],
        [op],
        ~s(the backfill of column "copy" on table "my_app_task" writes values breaking the ) <>
          "attribute's declared rules: must be at most 2 characters (2 rows) - change the " <>
          "expression or the rule"
      )
    end

    test "refuses a value not matching format", context do
      op = computed_add(:copy, :string, {:name, [:title]}, optional: true, format: ~r/^[a-z]+$/)

      assert_fill_refused(context, ["ok", "Not ok"], [op], ~r/must match .*\(1 row\)/)
    end

    test "refuses a value outside in", context do
      add_priority = %{
        op: :add_attribute,
        entity: MyApp.Task,
        name: :priority,
        type: :integer,
        opts: [optional: true, backfill: 7],
        line: 2
      }

      op = computed_add(:copy, :integer, {:name, [:priority]}, optional: true, in: 1..3)

      assert_fill_refused(context, ["one"], [add_priority, op], ~r/must be in 1\.\.3 \(1 row\)/)
    end

    test "refuses a value over a unique index's byte bound", context do
      op = computed_add(:copy, :string, {:name, [:title]}, optional: true, unique: true)

      assert_fill_refused(
        context,
        [String.duplicate("a", 3000)],
        [op],
        ~r/must hold at most \d+ bytes .*\(1 row\)/
      )
    end

    test "leaves nil alone and accepts values within the rules", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      term = {:at, {:split, {:name, [:title]}, {:value, ", "}}, {:value, 1}}
      op = computed_add(:copy, :string, term, optional: true, max_length: 2)

      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        insert_task("Paris, FR")
        insert_task("Porto")

        assert apply_file([op], create, first_model) == :ok

        assert rows_of("my_app_task", ["title", "copy"]) == [["Paris, FR", "FR"], ["Porto", nil]]
      end)
    end
  end

  describe "run/3, deleting and adding one name in a file" do
    setup %{chain: [create | _rest], first_model: first_model} do
      add_old =
        migration("20260813100000", [
          %{
            op: :add_attribute,
            entity: MyApp.Task,
            name: :note,
            type: :string,
            opts: [optional: true, backfill: "old"],
            line: 3
          }
        ])

      [add_old: add_old, create: create, first_model: first_model]
    end

    defp delete_note, do: %{op: :delete_attribute, entity: MyApp.Task, name: :note, line: 3}

    defp add_note_again(type, opts) do
      %{op: :add_attribute, entity: MyApp.Task, name: :note, type: type, opts: opts, line: 4}
    end

    defp replace_note(context, added) do
      %{add_old: add_old, create: create, first_model: first_model} = context
      old_model = Model.fold(first_model, add_old.ops)
      file = migration("20260813142237", [delete_note(), added])

      assert run([create], first_model, @context) == :ok

      insert_task("one")

      assert run([create, add_old], old_model, @context) == :ok
      assert run([create, add_old, file], Model.fold(old_model, file.ops), @context) == :ok
    end

    test "drops the old values", %{scratch: scratch} = context do
      route(scratch, fn ->
        replace_note(context, add_note_again(:string, optional: true))

        assert rows_of("my_app_task", ["title", "note", "note_$sort"]) == [["one", nil, nil]]
      end)
    end

    test "applies a constant backfill", %{scratch: scratch} = context do
      route(scratch, fn ->
        replace_note(context, add_note_again(:string, optional: true, backfill: "new"))

        assert rows_of("my_app_task", ["title", "note", "note_$sort"]) ==
                 [["one", "new", SortKey.compute("new")]]
      end)
    end

    test "applies a computed backfill", %{scratch: scratch} = context do
      backfill = %Value{term: {:name, [:title]}}

      route(scratch, fn ->
        replace_note(context, add_note_again(:string, optional: true, backfill: backfill))

        assert rows_of("my_app_task", ["title", "note"]) == [["one", "one"]]
      end)
    end

    test "takes another type without converting the old values", %{scratch: scratch} = context do
      route(scratch, fn ->
        replace_note(context, add_note_again(:integer, optional: true, backfill: 5))

        assert rows_of("my_app_task", ["title", "note"]) == [["one", 5]]
      end)
    end
  end
end
