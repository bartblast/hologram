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
  alias Hologram.Migration.Renderer
  alias Hologram.Migration.Value

  @context %{
    otp_app: "hologram",
    env: "test",
    hologram_version: "0.5.0",
    timestamp: ~U[2026-08-13 09:15:22.000000Z]
  }

  # A string attribute arriving on a populated table: its sort and search key companions
  # are computed from the value the backfill gives the existing rows. Past 64 bytes, so the
  # search key is a value rather than NULL, and holding a letter that folds to two, so a key
  # computed from the raw value fails.
  @note String.duplicate("Straße ", 12)

  # The values of the paged fills, as SQL over n: each folds to a key unlike itself, and the last
  # is past the key cap, so it takes a search key too.
  @paged_value ~s|CASE WHEN n = 1005 THEN repeat('Straße ', 12) ELSE 'Straße ' \|\| n END|

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
    INSERT INTO "hologram_data"."my_app_task" ("id", "title", "created_at", "server_created_at", "server_created_seq", "server_updated_at", "server_updated_seq", "updated_at", "$revisions")
    VALUES (gen_random_uuid(), $1, now(), now(), 0, now(), 0, now(), '{}')
    """

    {:ok, _result} = Connection.query(statement, [title])
  end

  defp insert_task(title, priority) do
    statement = """
    INSERT INTO "hologram_data"."my_app_task"
      ("id", "title", "priority", "created_at", "server_created_at", "server_created_seq", "server_updated_at", "server_updated_seq", "updated_at", "$revisions")
    VALUES (gen_random_uuid(), $1, $2, now(), now(), 0, now(), 0, now(), '{}')
    """

    Connection.query(statement, [title, priority])
  end

  defp migration(version, ops) do
    %{version: version, path: "app/migrations/#{version}.ex", ops: ops}
  end

  # What the column itself carries afterwards: whether it is required, and whether the
  # database holds a default for it.
  # Each row's keys, as computed from its value, so a key written from another row, copied raw or
  # left unwritten fails when the values allow it - @paged_value does.
  defp assert_keys(column) do
    {:ok, %{rows: keys}} =
      Connection.query(
        ~s|SELECT "#{column}", "#{column}_$sort", "#{column}_$search" | <>
          ~s|FROM "hologram_data"."my_app_task"|
      )

    assert Enum.all?(keys, fn [value, sort_key, search_key] ->
             sort_key == SortKey.compute(value) and search_key == SortKey.search_key(value)
           end)
  end

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
                ~s|"created_at", "server_created_at", "server_created_seq", | <>
                ~s|"server_updated_at", "server_updated_seq", "updated_at", | <>
                ~s|"$revisions") VALUES (gen_random_uuid(), $1, $2, now(), now(), 0, now(), 0, | <>
                ~s|now(), '{}') RETURNING "id"|,
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

  describe "run/3, computed backfill scenarios" do
    setup do
      attribute = fn entity, name, type, line ->
        %{
          op: :add_attribute,
          entity: entity,
          name: name,
          type: type,
          opts: [optional: true],
          line: line
        }
      end

      create =
        migration("20260813091522", [
          %{op: :create_entity, entity: MyApp.Place, line: 2},
          attribute.(MyApp.Place, :name, :string, 3),
          %{op: :create_entity, entity: MyApp.Tag, line: 4},
          attribute.(MyApp.Tag, :name, :string, 5),
          %{op: :create_entity, entity: MyApp.Task, line: 6},
          attribute.(MyApp.Task, :code, :string, 7),
          attribute.(MyApp.Task, :title, :string, 8),
          attribute.(MyApp.Task, :rank, :integer, 9),
          %{
            op: :add_relationship,
            entity: MyApp.Task,
            name: :place,
            type: MyApp.Place,
            opts: [optional: true],
            line: 10
          },
          %{
            op: :add_relationship,
            entity: MyApp.Task,
            name: :tags,
            type: [MyApp.Tag],
            opts: [],
            line: 11
          }
        ])

      [create: create, first_model: Model.fold(Model.empty(), create.ops)]
    end

    defp insert_row(table, values) do
      columns = Enum.map(values, fn {name, _value} -> ~s("#{name}") end)
      params = Enum.map(values, fn {_name, value} -> value end)

      placeholders =
        values
        |> Enum.with_index(1)
        |> Enum.map(fn {_value, position} -> "$#{position}" end)

      statement =
        ~s|INSERT INTO "hologram_data"."#{table}" | <>
          ~s|("id", #{Enum.join(columns, ", ")}, "created_at", "server_created_at", | <>
          ~s|"server_created_seq", "server_updated_at", "server_updated_seq", "updated_at", | <>
          ~s|"$revisions") VALUES (gen_random_uuid(), #{Enum.join(placeholders, ", ")}, | <>
          ~s|now(), now(), 0, now(), 0, now(), '{}') RETURNING "id"|

      {:ok, %{rows: [[id]]}} = Connection.query(statement, params)

      id
    end

    defp link_tag(task_id, name) do
      tag_id = insert_row("my_app_tag", name: name)

      {:ok, _result} =
        Connection.query(
          ~s|INSERT INTO "hologram_data"."my_app_task_tags_$join" | <>
            ~s|("source_id", "target_id") VALUES ($1, $2)|,
          [task_id, tag_id]
        )
    end

    defp rows_by_code(columns) do
      select_list = Enum.map_join(columns, ", ", &~s("#{&1}"))

      {:ok, %{rows: rows}} =
        Connection.query(
          ~s(SELECT #{select_list} FROM "hologram_data"."my_app_task" ORDER BY "code")
        )

      rows
    end

    defp apply_scenario(%{create: create, first_model: first_model, scratch: scratch}, rows, ops) do
      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        rows.()

        assert apply_file(ops, create, first_model) == :ok
      end)
    end

    test "splits a column in two and deletes it in one file", %{scratch: scratch} = context do
      part = fn index -> {:at, {:split, {:name, [:title]}, {:value, ", "}}, {:value, index}} end

      ops = [
        computed_add(:city, :string, part.(0), optional: true),
        computed_add(:country, :string, part.(1), optional: true),
        %{op: :delete_attribute, entity: MyApp.Task, name: :title, line: 5}
      ]

      rows = fn ->
        insert_row("my_app_task", code: "a", title: "Paris, France")
        insert_row("my_app_task", code: "b", title: "Porto")
      end

      apply_scenario(context, rows, ops)

      route(scratch, fn ->
        assert rows_by_code(["city", "country"]) == [["Paris", "France"], ["Porto", nil]]
        refute has_column?("my_app_task", "title")
      end)
    end

    test "merges two columns into one", %{scratch: scratch} = context do
      term = {:coalesce, [{:name, [:title]}, {:concat, [{:name, [:code]}, {:value, "?"}]}]}

      rows = fn ->
        insert_row("my_app_task", code: "a", title: "One")
        insert_row("my_app_task", code: "b", title: nil)
      end

      apply_scenario(context, rows, [computed_add(:label, :string, term, optional: true)])

      route(scratch, fn ->
        assert rows_by_code(["label"]) == [["One"], ["b?"]]
      end)
    end

    test "reads a field through a to-one", %{scratch: scratch} = context do
      rows = fn ->
        insert_row("my_app_place", name: "Bergen")
        place_id = insert_row("my_app_place", name: "Oslo")

        insert_row("my_app_task", code: "a", place_id: place_id)
        insert_row("my_app_task", code: "b", place_id: nil)
      end

      ops = [computed_add(:city, :string, {:name, [:place, :name]}, optional: true)]

      apply_scenario(context, rows, ops)

      route(scratch, fn ->
        assert rows_by_code(["city"]) == [["Oslo"], [nil]]
      end)
    end

    test "counts and picks the most common over a join table", %{scratch: scratch} = context do
      rows = fn ->
        task_id = insert_row("my_app_task", code: "a")

        Enum.each(["y", "x", "y"], &link_tag(task_id, &1))

        insert_row("my_app_task", code: "b")
      end

      ops = [
        computed_add(:tag_count, :integer, {:count, {:relationship, [:tags]}}, optional: true),
        computed_add(
          :main_tag,
          :string,
          {:most_common, {:relationship, [:tags]}, :name},
          optional: true
        )
      ]

      apply_scenario(context, rows, ops)

      route(scratch, fn ->
        assert rows_by_code(["tag_count", "main_tag"]) == [[3, "y"], [0, nil]]
      end)
    end

    test "reads an attribute an earlier op added with a constant backfill",
         %{scratch: scratch} = context do
      ops = [
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :prefix,
          type: :string,
          opts: [backfill: "n-"],
          line: 2
        },
        computed_add(
          :label,
          :string,
          {:concat, [{:name, [:prefix]}, {:name, [:code]}]},
          optional: true
        )
      ]

      apply_scenario(context, fn -> insert_row("my_app_task", code: "a") end, ops)

      route(scratch, fn ->
        assert rows_by_code(["label"]) == [["n-a"]]
      end)
    end

    test "reads an attribute whose type an earlier op changed", %{scratch: scratch} = context do
      ops = [
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :rank,
          changes: [type: :string],
          line: 2
        },
        # COALESCE refuses a bigint beside text, so this fails if the fill runs before the change.
        computed_add(
          :label,
          :string,
          {:coalesce, [{:name, [:rank]}, {:value, "none"}]},
          optional: true
        )
      ]

      apply_scenario(context, fn -> insert_row("my_app_task", code: "a", rank: 5) end, ops)

      route(scratch, fn ->
        assert rows_by_code(["rank", "label"]) == [["5", "5"]]
      end)
    end

    test "reads an attribute under the name an earlier op gave it",
         %{scratch: scratch} = context do
      ops = [
        %{op: :rename_attribute, entity: MyApp.Task, from: :title, to: :heading, line: 2},
        computed_add(:copy, :string, {:name, [:heading]}, optional: true)
      ]

      apply_scenario(context, fn -> insert_row("my_app_task", code: "a", title: "One") end, ops)

      route(scratch, fn ->
        assert rows_by_code(["heading", "copy"]) == [["One", "One"]]
      end)
    end

    test "fills the sort and search keys of a computed string", %{scratch: scratch} = context do
      ops = [computed_add(:copy, :string, {:name, [:title]}, optional: true)]

      apply_scenario(context, fn -> insert_row("my_app_task", code: "a", title: @note) end, ops)

      route(scratch, fn ->
        assert rows_by_code(["copy", "copy_$sort", "copy_$search"]) == [
                 [@note, SortKey.compute(@note), SortKey.search_key(@note)]
               ]
      end)
    end

    test "refuses a unique attribute whose computed values repeat, schema unchanged", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      ops = [computed_add(:copy, :string, {:name, [:title]}, optional: true, unique: true)]

      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        insert_row("my_app_task", code: "a", title: "same")
        insert_row("my_app_task", code: "b", title: "same")

        assert_error RuntimeError,
                     ~r/found 1 duplicate key in "my_app_task" over \("copy"\)/,
                     fn ->
                       apply_file(ops, create, first_model)
                     end

        refute has_column?("my_app_task", "copy")
      end)
    end
  end

  describe "run/3, a backfill on a tightening" do
    setup do
      attribute = fn name, type, opts, line ->
        %{op: :add_attribute, entity: MyApp.Task, name: name, type: type, opts: opts, line: line}
      end

      create =
        migration("20260813091522", [
          %{op: :create_entity, entity: MyApp.Task, line: 2},
          attribute.(:code, :string, [optional: true], 3),
          attribute.(:title, :string, [optional: true], 4),
          attribute.(:rank, :integer, [optional: true], 5),
          attribute.(:slug, :string, [optional: true, unique: true], 6)
        ])

      [create: create, first_model: Model.fold(Model.empty(), create.ops)]
    end

    defp tighten(name, backfill, changes \\ []) do
      %{
        op: :change_attribute,
        entity: MyApp.Task,
        name: name,
        changes: [optional: false, backfill: backfill] ++ changes,
        line: 3
      }
    end

    defp copy_of(name), do: %Value{term: {:name, [name]}}

    defp nullable?(column), do: not column_flags("my_app_task", column).not_null

    # A key no fill computes, so a row the fill leaves alone is told from one it wrote.
    defp insert_keyed(code, title) do
      insert_row("my_app_task", [
        {"code", code},
        {"title", title},
        {"title_$sort", "kept-key"}
      ])
    end

    for {label, backfill} <- [
          {"constant", "filled"},
          {"computed", quote(do: %Value{term: {:value, "filled"}})}
        ] do
      test "fills only the rows holding nil with a #{label} backfill",
           %{scratch: scratch} = context do
        rows = fn ->
          insert_keyed("a", "kept")
          insert_row("my_app_task", code: "b")
        end

        apply_scenario(context, rows, [tighten(:title, unquote(backfill))])

        route(scratch, fn ->
          assert rows_by_code(["title", "title_$sort", "title_$search"]) == [
                   ["kept", "kept-key", nil],
                   ["filled", SortKey.compute("filled"), SortKey.search_key("filled")]
                 ]

          refute nullable?("title")
        end)
      end
    end

    test "fills each row from its own fields", %{scratch: scratch} = context do
      rows = fn ->
        insert_row("my_app_task", code: "a", title: "kept")
        insert_row("my_app_task", code: "b")
        insert_row("my_app_task", code: "c")
      end

      apply_scenario(context, rows, [tighten(:title, copy_of(:code))])

      route(scratch, fn ->
        assert rows_by_code(["title"]) == [["kept"], ["b"], ["c"]]
      end)
    end

    test "fills an enum attribute from another", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      enums =
        migration("20260813142236", [
          %{
            op: :add_attribute,
            entity: MyApp.Task,
            name: :source,
            type: :enum,
            opts: [optional: true, values: [:a, :b]],
            line: 2
          },
          %{
            op: :add_attribute,
            entity: MyApp.Task,
            name: :target,
            type: :enum,
            opts: [optional: true, values: [:a, :b]],
            line: 3
          }
        ])

      enum_model = Model.fold(first_model, enums.ops)
      file = migration("20260813142237", [tighten(:target, copy_of(:source))])

      route(scratch, fn ->
        assert run([create, enums], enum_model, @context) == :ok

        insert_row("my_app_task", [{"code", "a"}, {"source", "b"}])

        assert run([create, enums, file], Model.fold(enum_model, file.ops), @context) == :ok
        assert rows_by_code(["target"]) == [["b"]]
      end)
    end

    test "fills more rows holding nil than a page, each with its keys",
         %{scratch: scratch} = context do
      rows = fn ->
        {:ok, _result} =
          Connection.query(
            ~s|INSERT INTO "hologram_data"."my_app_task" ("id", "code", "created_at", | <>
              ~s|"server_created_at", "server_created_seq", | <>
              ~s|"server_updated_at", "server_updated_seq", "updated_at", "$revisions") | <>
              ~s|SELECT gen_random_uuid(), #{@paged_value}, now(), now(), 0, now(), 0, now(), | <>
              ~s|'{}' | <>
              ~s|FROM generate_series(1, 1005) AS n|
          )
      end

      apply_scenario(context, rows, [tighten(:title, copy_of(:code))])

      route(scratch, fn ->
        {:ok, %{rows: [[total, wrong]]}} =
          Connection.query(
            ~s|SELECT COUNT(*), COUNT(*) FILTER (WHERE "title" IS DISTINCT FROM "code" OR "title_$sort" IS NULL) | <>
              ~s|FROM "hologram_data"."my_app_task"|
          )

        assert total == 1005
        assert wrong == 0

        assert_keys("title")
      end)
    end

    test "fills two tightenings of one file", %{scratch: scratch} = context do
      ops = [tighten(:title, copy_of(:code)), tighten(:slug, copy_of(:code))]

      apply_scenario(context, fn -> insert_row("my_app_task", code: "a") end, ops)

      route(scratch, fn ->
        assert rows_by_code(["title", "slug"]) == [["a", "a"]]
      end)
    end

    test "tightens with nothing to fill", %{scratch: scratch} = context do
      rows = fn -> insert_row("my_app_task", code: "a", title: "kept") end

      apply_scenario(context, rows, [tighten(:title, copy_of(:code))])

      route(scratch, fn ->
        assert rows_by_code(["title"]) == [["kept"]]
        refute nullable?("title")
      end)
    end

    test "refuses a row the expression leaves nil, schema unchanged", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        insert_row("my_app_task", code: "a", rank: 1)
        insert_row("my_app_task", code: nil, rank: 2)

        assert_error RuntimeError,
                     ~s(the backfill of column "title" on table "my_app_task" leaves 1 row ) <>
                       "without a value - give the expression a value for them, like " <>
                       "coalesce(..., <value>), or keep optional: true on the attribute in the " <>
                       "entity type and remove optional: false and backfill: from the op, or the whole op " <>
                       "when it changes nothing else",
                     fn ->
                       apply_file([tighten(:title, copy_of(:code))], create, first_model)
                     end

        assert rows_by_code(["title"]) == [[nil], [nil]]
        assert nullable?("title")
      end)
    end

    for {label, backfill} <- [
          {"constant", "same"},
          {"computed", quote(do: %Value{term: {:name, [:title]}})}
        ] do
      test "refuses a #{label} backfill making a standing unique key repeat", %{
        create: create,
        first_model: first_model,
        scratch: scratch
      } do
        route(scratch, fn ->
          assert run([create], first_model, @context) == :ok

          insert_row("my_app_task", code: "a", title: "same")
          insert_row("my_app_task", code: "b", title: "same")

          assert_error RuntimeError,
                       ~s(cannot make column "slug" on table "my_app_task" required - filling ) <>
                         ~s{its NULLs with the backfill would make 1 key repeat over ("slug") - } <>
                         "fix the data or the backfill, drop the unique declaration before the " <>
                         "op, or keep optional: true on the attribute in the entity type and " <>
                         "remove optional: false and backfill: from the op, or the whole op when " <>
                         "it changes nothing else",
                       fn ->
                         apply_file([tighten(:slug, unquote(backfill))], create, first_model)
                       end

          assert rows_by_code(["slug"]) == [[nil], [nil]]
        end)
      end
    end

    test "passes a computed key that repeats no other row", %{scratch: scratch} = context do
      rows = fn ->
        insert_row("my_app_task", code: "a", slug: "b")
        insert_row("my_app_task", code: "c")
      end

      apply_scenario(context, rows, [tighten(:slug, copy_of(:code))])

      route(scratch, fn ->
        assert rows_by_code(["slug"]) == [["b"], ["c"]]
      end)
    end

    test "wins over the declared default", %{scratch: scratch} = context do
      ops = [tighten(:title, "filled", default: "declared")]

      apply_scenario(context, fn -> insert_row("my_app_task", code: "a") end, ops)

      route(scratch, fn ->
        assert rows_by_code(["title"]) == [["filled"]]
      end)
    end

    test "judges only the filled rows against a format", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      op = tighten(:title, copy_of(:code), format: ~r/^[a-z]+$/)

      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        insert_row("my_app_task", code: "a", title: "kept")
        insert_row("my_app_task", code: "BAD")

        assert_error RuntimeError, ~r/must match .*\(1 row\)/, fn ->
          apply_file([op], create, first_model)
        end

        assert nullable?("title")
      end)
    end

    test "leaves a retained value the format would refuse", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      op = tighten(:title, copy_of(:code), format: ~r/^[a-z]+$/)

      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        insert_row("my_app_task", code: "a", title: "Kept As Is")
        insert_row("my_app_task", code: "b")

        assert apply_file([op], create, first_model) == :ok

        assert rows_by_code(["title"]) == [["Kept As Is"], ["b"]]
        refute nullable?("title")
      end)
    end

    test "offers no default to a unique attribute meeting a nil", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      op = %{
        op: :change_attribute,
        entity: MyApp.Task,
        name: :slug,
        changes: [optional: false],
        line: 3
      }

      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        insert_row("my_app_task", code: "a")

        assert_error RuntimeError,
                     ~s(cannot make column "slug" on table "my_app_task" required - ) <>
                       "found 1 row with NULL - add backfill: <value or expression> to the op, " <>
                       "keep the attribute optional: true, or fix the data",
                     fn -> apply_file([op], create, first_model) end
      end)
    end

    test "takes a type the attribute has already as no type change", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      op = %{
        op: :change_attribute,
        entity: MyApp.Task,
        name: :title,
        changes: [type: :string, optional: false],
        line: 3
      }

      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        insert_row("my_app_task", code: "a")

        assert_error RuntimeError,
                     ~s(cannot make column "title" on table "my_app_task" required - ) <>
                       "found 1 row with NULL - add backfill: <value or expression> to the op, " <>
                       "declare default: <value>, keep the attribute optional: true, or fix the " <>
                       "data",
                     fn -> apply_file([op], create, first_model) end
      end)
    end

    test "names a separate op when a tightening beside a type change meets a nil", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      op = %{
        op: :change_attribute,
        entity: MyApp.Task,
        name: :rank,
        changes: [optional: false, type: :string],
        line: 3
      }

      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        insert_row("my_app_task", code: "a")

        assert_error RuntimeError,
                     ~s(cannot make column "rank" on table "my_app_task" required - ) <>
                       "found 1 row with NULL - change the type in an op of its own, then add " <>
                       "backfill: <value or expression> to the op making it required, keep the " <>
                       "attribute optional: true, or fix the data",
                     fn -> apply_file([op], create, first_model) end
      end)
    end

    test "applies a type change and a constant tightening of one attribute",
         %{scratch: scratch} = context do
      ops = [
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :rank,
          changes: [type: :string],
          line: 2
        },
        tighten(:rank, "0")
      ]

      rows = fn ->
        insert_row("my_app_task", code: "a", rank: 5)
        insert_row("my_app_task", code: "b")
      end

      apply_scenario(context, rows, ops)

      route(scratch, fn ->
        assert rows_by_code(["rank"]) == [["5"], ["0"]]
      end)
    end

    test "refuses a value too long for a standing unique index before writing it", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      long = String.duplicate("x", 3000)

      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        insert_row("my_app_task", code: long)

        assert_error RuntimeError, ~r/must hold at most \d+ bytes .*\(1 row\)/, fn ->
          apply_file([tighten(:slug, copy_of(:code))], create, first_model)
        end

        assert rows_by_code(["slug"]) == [[nil]]
      end)
    end
  end

  describe "run/3, a backfill on a to-one relationship" do
    @missing_id "018f0000-0000-7000-8000-00000000dead"

    setup do
      attribute = fn entity, name, line ->
        %{
          op: :add_attribute,
          entity: entity,
          name: name,
          type: :string,
          opts: [optional: true],
          line: line
        }
      end

      relationship = fn entity, name, type, line ->
        %{
          op: :add_relationship,
          entity: entity,
          name: name,
          type: type,
          opts: [optional: true],
          line: line
        }
      end

      create =
        migration("20260813091522", [
          %{op: :create_entity, entity: MyApp.User, line: 2},
          %{op: :create_entity, entity: MyApp.Tag, line: 3},
          relationship.(MyApp.Tag, :owner, MyApp.User, 4),
          %{op: :create_entity, entity: MyApp.Task, line: 5},
          attribute.(MyApp.Task, :code, 6),
          relationship.(MyApp.Task, :creator, MyApp.User, 7),
          relationship.(MyApp.Task, :reviewer, MyApp.User, 8),
          %{
            op: :add_relationship,
            entity: MyApp.Task,
            name: :tags,
            type: [MyApp.Tag],
            opts: [],
            line: 9
          },
          %{op: :create_entity, entity: MyApp.Stop, line: 10},
          attribute.(MyApp.Stop, :code, 11),
          relationship.(MyApp.Stop, :task, MyApp.Task, 12)
        ])

      [create: create, first_model: Model.fold(Model.empty(), create.ops)]
    end

    defp add_to_one(entity \\ MyApp.Task, backfill, opts \\ []) do
      %{
        op: :add_relationship,
        entity: entity,
        name: :owner,
        type: MyApp.User,
        opts: Keyword.put(opts, :backfill, backfill),
        line: 3
      }
    end

    defp tighten_reviewer(backfill) do
      %{
        op: :change_relationship,
        entity: MyApp.Task,
        name: :reviewer,
        changes: [optional: false, backfill: backfill],
        line: 3
      }
    end

    defp user_id do
      {:ok, %{rows: [[id]]}} =
        Connection.query(
          ~s|INSERT INTO "hologram_data"."my_app_user" ("id", "created_at", | <>
            ~s|"server_created_at", "server_created_seq", | <>
            ~s|"server_updated_at", "server_updated_seq", "updated_at", "$revisions") | <>
            ~s|VALUES (gen_random_uuid(), now(), now(), 0, now(), 0, now(), '{}') | <>
            ~s|RETURNING "id"::text|
        )

      id
    end

    defp uuid(text), do: Ecto.UUID.dump!(text)

    defp ids_by_code(table, column) do
      {:ok, %{rows: rows}} =
        Connection.query(
          ~s|SELECT "#{column}"::text FROM "hologram_data"."#{table}" ORDER BY "code"|
        )

      List.flatten(rows)
    end

    defp owner_column_required? do
      column_flags("my_app_task", "owner_id").not_null
    end

    test "fills a required to-one with a constant id", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        admin = user_id()
        insert_row("my_app_task", code: "a")

        assert apply_file([add_to_one(admin)], create, first_model) == :ok
        assert ids_by_code("my_app_task", "owner_id") == [admin]
        assert owner_column_required?()
      end)
    end

    test "fills a to-one from a reference of the row, falling back to a pinned id", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        admin = user_id()
        creator = user_id()

        insert_row("my_app_task", code: "a", creator_id: uuid(creator))
        insert_row("my_app_task", code: "b")

        term = {:coalesce, [{:name, [:creator_id]}, {:value, admin}]}

        assert apply_file([add_to_one(%Value{term: term})], create, first_model) == :ok
        assert ids_by_code("my_app_task", "owner_id") == [creator, admin]
        assert owner_column_required?()
      end)
    end

    test "fills a to-one through a to-one path", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        creator = user_id()
        task_id = insert_row("my_app_task", code: "a", creator_id: uuid(creator))
        insert_row("my_app_stop", code: "s", task_id: task_id)

        op = add_to_one(MyApp.Stop, %Value{term: {:name, [:task, :creator_id]}})

        assert apply_file([op], create, first_model) == :ok
        assert ids_by_code("my_app_stop", "owner_id") == [creator]
      end)
    end

    test "fills a to-one with the most common reference of a set", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        common = user_id()
        rare = user_id()
        task_id = insert_row("my_app_task", code: "a")

        for owner <- [rare, common, common] do
          tag_id = insert_row("my_app_tag", owner_id: uuid(owner))

          {:ok, _result} =
            Connection.query(
              ~s|INSERT INTO "hologram_data"."my_app_task_tags_$join" | <>
                ~s|("source_id", "target_id") VALUES ($1, $2)|,
              [task_id, tag_id]
            )
        end

        term = {:most_common, {:relationship, [:tags]}, :owner_id}

        assert apply_file([add_to_one(%Value{term: term})], create, first_model) == :ok
        assert ids_by_code("my_app_task", "owner_id") == [common]
      end)
    end

    test "refuses a required to-one the expression leaves nil on an add", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        insert_row("my_app_task", code: "a")

        assert_error RuntimeError,
                     ~s(the backfill of column "owner_id" on table "my_app_task" leaves 1 row ) <>
                       "without a value - give the expression a value for them, like " <>
                       "coalesce(..., <value>), or make the relationship optional: true",
                     fn ->
                       apply_file(
                         [add_to_one(%Value{term: {:name, [:creator_id]}})],
                         create,
                         first_model
                       )
                     end

        refute has_column?("my_app_task", "owner_id")
      end)
    end

    for {label, backfill} <- [
          {"constant", :id},
          {"computed", quote(do: %Value{term: {:name, [:creator_id]}})}
        ] do
      test "refuses a #{label} backfill making a unique to-one repeat, naming the relationship",
           %{
             create: create,
             first_model: first_model,
             scratch: scratch
           } do
        unique =
          migration("20260813120000", [
            %{
              op: :change_relationship,
              entity: MyApp.Task,
              name: :reviewer,
              changes: [unique: true],
              line: 3
            }
          ])

        unique_model = Model.fold(first_model, unique.ops)

        route(scratch, fn ->
          assert run([create, unique], unique_model, @context) == :ok

          creator = user_id()
          insert_row("my_app_task", code: "a", creator_id: uuid(creator))
          insert_row("my_app_task", code: "b", creator_id: uuid(creator))

          backfill = if unquote(backfill) == :id, do: creator, else: unquote(backfill)
          file = migration("20260813142237", [tighten_reviewer(backfill)])

          assert_error RuntimeError,
                       ~s(cannot make column "reviewer_id" on table "my_app_task" required - ) <>
                         "filling its NULLs with the backfill would make 1 key repeat over " <>
                         ~s{("reviewer_id") - fix the data or the backfill, drop the unique } <>
                         "declaration before the op, or keep optional: true on the relationship " <>
                         "in the entity type and remove optional: false and backfill: from the " <>
                         "op, or the whole op when it changes nothing else",
                       fn ->
                         run([create, unique, file], Model.fold(unique_model, file.ops), @context)
                       end

          assert ids_by_code("my_app_task", "reviewer_id") == [nil, nil]
        end)
      end
    end

    test "refuses a to-one tightening the expression leaves nil, rows unchanged", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        insert_row("my_app_task", code: "a")

        assert_error RuntimeError,
                     ~s(the backfill of column "reviewer_id" on table "my_app_task" leaves 1 ) <>
                       "row without a value - give the expression a value for them, like " <>
                       "coalesce(..., <value>), or keep optional: true on the relationship in " <>
                       "the entity type and remove optional: false and backfill: from the op, or the " <>
                       "whole op when it changes nothing else",
                     fn ->
                       apply_file(
                         [tighten_reviewer(%Value{term: {:name, [:creator_id]}})],
                         create,
                         first_model
                       )
                     end

        assert ids_by_code("my_app_task", "reviewer_id") == [nil]
      end)
    end

    for {label, backfill} <- [
          {"constant", "018f0000-0000-7000-8000-00000000dead"},
          {"computed", quote(do: %Value{term: {:value, "018f0000-0000-7000-8000-00000000dead"}})}
        ] do
      test "refuses a #{label} id no row holds on an add, schema unchanged", %{
        create: create,
        first_model: first_model,
        scratch: scratch
      } do
        route(scratch, fn ->
          assert run([create], first_model, @context) == :ok

          insert_row("my_app_task", code: "a")

          assert_error RuntimeError,
                       ~s(the backfill of column "owner_id" on table "my_app_task" writes ) <>
                         "#{@missing_id}, which no MyApp.User holds - change the backfill " <>
                         "or add that row",
                       fn ->
                         apply_file([add_to_one(unquote(backfill))], create, first_model)
                       end

          refute has_column?("my_app_task", "owner_id")
        end)
      end

      test "refuses a #{label} id no row holds on a tightening, rows unchanged", %{
        create: create,
        first_model: first_model,
        scratch: scratch
      } do
        route(scratch, fn ->
          assert run([create], first_model, @context) == :ok

          insert_row("my_app_task", code: "a")

          assert_error RuntimeError,
                       ~s(the backfill of column "reviewer_id" on table "my_app_task" writes ) <>
                         "#{@missing_id}, which no MyApp.User holds - change the backfill " <>
                         "or add that row",
                       fn ->
                         apply_file([tighten_reviewer(unquote(backfill))], create, first_model)
                       end

          assert ids_by_code("my_app_task", "reviewer_id") == [nil]
        end)
      end
    end

    test "fills only the rows holding nil on a constant tightening", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        admin = user_id()
        kept = user_id()

        insert_row("my_app_task", code: "a", reviewer_id: uuid(kept))
        insert_row("my_app_task", code: "b")

        assert apply_file([tighten_reviewer(admin)], create, first_model) == :ok
        assert ids_by_code("my_app_task", "reviewer_id") == [kept, admin]
        assert column_flags("my_app_task", "reviewer_id").not_null
      end)
    end

    test "fills only the rows holding nil on a computed tightening", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        creator = user_id()
        kept = user_id()

        insert_row("my_app_task", code: "a", creator_id: uuid(creator), reviewer_id: uuid(kept))
        insert_row("my_app_task", code: "b", creator_id: uuid(creator))

        op = tighten_reviewer(%Value{term: {:name, [:creator_id]}})

        assert apply_file([op], create, first_model) == :ok
        assert ids_by_code("my_app_task", "reviewer_id") == [kept, creator]
      end)
    end

    test "doesn't give a deleted to-one's backfill to the one added again", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        admin = user_id()
        insert_row("my_app_task", code: "a")

        ops = [
          add_to_one(admin),
          %{op: :delete_relationship, entity: MyApp.Task, name: :owner, line: 4},
          %{
            op: :add_relationship,
            entity: MyApp.Task,
            name: :owner,
            type: MyApp.User,
            opts: [optional: true],
            line: 5
          }
        ]

        assert apply_file(ops, create, first_model) == :ok
        assert ids_by_code("my_app_task", "owner_id") == [nil]
      end)
    end

    test "doesn't give a deleted attribute's backfill to the one added again", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      add_note = fn opts ->
        %{op: :add_attribute, entity: MyApp.Task, name: :note, type: :string, opts: opts, line: 3}
      end

      ops = [
        add_note.(backfill: "old"),
        %{op: :delete_attribute, entity: MyApp.Task, name: :note, line: 4},
        add_note.(optional: true)
      ]

      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        insert_row("my_app_task", code: "a")

        assert apply_file(ops, create, first_model) == :ok
        assert ids_by_code("my_app_task", "note") == [nil]
      end)
    end

    test "names backfill and no default when a plain tightening meets a nil", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      op = %{
        op: :change_relationship,
        entity: MyApp.Task,
        name: :reviewer,
        changes: [optional: false],
        line: 3
      }

      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        insert_row("my_app_task", code: "a")

        assert_error RuntimeError,
                     ~s(cannot make column "reviewer_id" on table "my_app_task" required - ) <>
                       "found 1 row with NULL - add backfill: <id or expression> to the op, " <>
                       "keep the relationship optional: true, or fix the data",
                     fn -> apply_file([op], create, first_model) end
      end)
    end

    test "names a separate op when a retarget beside a tightening meets a nil", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      op = %{
        op: :change_relationship,
        entity: MyApp.Task,
        name: :reviewer,
        changes: [type: MyApp.Tag, optional: false],
        line: 3
      }

      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        insert_row("my_app_task", code: "a")

        assert_error RuntimeError,
                     ~s(cannot make column "reviewer_id" on table "my_app_task" required - ) <>
                       "found 1 row with NULL - change the type in an op of its own, then add " <>
                       "backfill: <id or expression> to the op making it required, keep the " <>
                       "relationship optional: true, or fix the data",
                     fn -> apply_file([op], create, first_model) end
      end)
    end

    test "applies a chain with a pinned id to an empty database", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      route(scratch, fn ->
        assert apply_file([add_to_one(@missing_id)], create, first_model) == :ok
        assert column_flags("my_app_task", "owner_id").not_null
      end)
    end

    test "refuses a constant that isn't an id", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      route(scratch, fn ->
        assert_error Hologram.CompileError,
                     ~r/holds "nope", which isn't the id of a MyApp.User/,
                     fn ->
                       apply_file([add_to_one("nope")], create, first_model)
                     end
      end)
    end
  end

  describe "run/3, a fn reading the rows pointing at this one" do
    setup do
      attribute = fn entity, name, line ->
        %{
          op: :add_attribute,
          entity: entity,
          name: name,
          type: :string,
          opts: [optional: true],
          line: line
        }
      end

      create =
        migration("20260813091522", [
          %{op: :create_entity, entity: MyApp.Task, line: 2},
          attribute.(MyApp.Task, :code, 3),
          %{op: :create_entity, entity: MyApp.Stop, line: 4},
          attribute.(MyApp.Stop, :currency, 5),
          %{
            op: :add_relationship,
            entity: MyApp.Stop,
            name: :task,
            type: MyApp.Task,
            opts: [optional: true],
            line: 6
          }
        ])

      [create: create, first_model: Model.fold(Model.empty(), create.ops)]
    end

    defp referencing_rows do
      busy = insert_row("my_app_task", code: "a")
      insert_row("my_app_task", code: "b")

      for currency <- ["USD", "EUR", "EUR"] do
        insert_row("my_app_stop", currency: currency, task_id: busy)
      end

      insert_row("my_app_stop", currency: "GBP")
    end

    test "fills a count and a most_common", %{scratch: scratch} = context do
      set = {:referencing, MyApp.Stop, :task}

      ops = [
        computed_add(:stop_count, :integer, {:count, set}, optional: true),
        computed_add(:currency, :string, {:most_common, set, :currency}, optional: true)
      ]

      apply_scenario(context, &referencing_rows/0, ops)

      route(scratch, fn ->
        assert rows_by_code(["stop_count", "currency"]) == [[3, "EUR"], [0, nil]]
      end)
    end

    test "reads them through one join, with no index on the reference", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      op = computed_add(:stop_count, :integer, {:count, {:referencing, MyApp.Stop, :task}}, [])

      %{transactional: ops} = Renderer.render([op], first_model)

      assert %{sql: {fragment, joins, []}} = Enum.find(ops, &(&1.op == :fill_column))
      refute fragment =~ "SELECT"
      assert length(String.split(joins, "GROUP BY")) == 2
      assert length(String.split(joins, "JOIN")) == 2

      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        {:ok, %{rows: indexes}} =
          Connection.query(
            "SELECT indexdef FROM pg_indexes WHERE schemaname = 'hologram_data' " <>
              "AND tablename = 'my_app_stop'"
          )

        refute Enum.any?(indexes, fn [definition] -> definition =~ "task_id" end)
      end)
    end

    test "fills only the rows holding nil on a tightening", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      add =
        migration("20260813100000", [
          %{
            op: :add_attribute,
            entity: MyApp.Task,
            name: :stop_count,
            type: :integer,
            opts: [optional: true],
            line: 2
          }
        ])

      added_model = Model.fold(first_model, add.ops)

      tighten =
        migration("20260813142237", [
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :stop_count,
            changes: [
              optional: false,
              backfill: %Value{args: [:id], term: {:count, {:referencing, MyApp.Stop, :task}}}
            ],
            line: 3
          }
        ])

      route(scratch, fn ->
        assert run([create, add], added_model, @context) == :ok

        referencing_rows()
        insert_row("my_app_task", [{"code", "c"}, {"stop_count", 7}])

        assert run([create, add, tighten], Model.fold(added_model, tighten.ops), @context) == :ok
        assert rows_by_code(["stop_count"]) == [[3], [0], [7]]
      end)
    end

    test "reads the row itself beside the join", %{scratch: scratch} = context do
      term =
        {:concat,
         [
           {:name, [:code]},
           {:value, ":"},
           {:most_common, {:referencing, MyApp.Stop, :task}, :currency}
         ]}

      apply_scenario(context, &referencing_rows/0, [
        computed_add(:label, :string, term, optional: true)
      ])

      route(scratch, fn ->
        assert rows_by_code(["label"]) == [["a:EUR"], [nil]]
      end)
    end
  end

  describe "run/3, an Elixir fn" do
    setup do
      attribute = fn name, type, opts, line ->
        %{op: :add_attribute, entity: MyApp.Task, name: name, type: type, opts: opts, line: line}
      end

      create =
        migration("20260813091522", [
          %{op: :create_entity, entity: MyApp.User, line: 2},
          %{op: :create_entity, entity: MyApp.Task, line: 3},
          attribute.(:code, :string, [optional: true], 4),
          attribute.(:title, :string, [optional: true], 5),
          attribute.(:rank, :integer, [optional: true], 6),
          attribute.(:slug, :string, [optional: true, unique: true], 7),
          %{
            op: :add_relationship,
            entity: MyApp.Task,
            name: :creator,
            type: MyApp.User,
            opts: [optional: true],
            line: 8
          }
        ])

      [create: create, first_model: Model.fold(Model.empty(), create.ops)]
    end

    # The function a compiled migration's fn becomes, with the term its op would carry.
    defp elixir_fn(body) do
      module =
        compile_migration("20260813091599", """
        change_entity MyApp.Trip do
          add_attribute :value, :string, backfill: #{body}
        end
        """)

      [op] = module.__hologram_migration__().ops

      op.opts[:backfill]
    end

    defp add_filled(name, type, value, opts \\ []) do
      %{
        op: :add_attribute,
        entity: MyApp.Task,
        name: name,
        type: type,
        opts: Keyword.put(opts, :backfill, value),
        line: 3
      }
    end

    defp tighten_title(value) do
      %{
        op: :change_attribute,
        entity: MyApp.Task,
        name: :title,
        changes: [optional: false, backfill: value],
        line: 3
      }
    end

    defp assert_row_fill_refused(context, rows, ops, message) do
      %{create: create, first_model: first_model, scratch: scratch} = context

      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        rows.()

        assert_error RuntimeError, message, fn -> apply_file(ops, create, first_model) end
      end)
    end

    test "fills over more rows than a page, each with its keys",
         %{scratch: scratch} = context do
      rows = fn ->
        {:ok, _result} =
          Connection.query(
            ~s|INSERT INTO "hologram_data"."my_app_task" ("id", "title", "created_at", | <>
              ~s|"server_created_at", "server_created_seq", | <>
              ~s|"server_updated_at", "server_updated_seq", "updated_at", "$revisions") | <>
              ~s|SELECT gen_random_uuid(), #{@paged_value}, now(), now(), 0, now(), 0, now(), | <>
              ~s|'{}' | <>
              ~s|FROM generate_series(1, 1005) AS n|
          )
      end

      value = elixir_fn("fn title -> String.downcase(title) end")

      apply_scenario(context, rows, [add_filled(:copy, :string, value, optional: true)])

      route(scratch, fn ->
        {:ok, %{rows: [[total, wrong]]}} =
          Connection.query(
            ~s|SELECT COUNT(*), COUNT(*) FILTER (WHERE "copy" IS DISTINCT FROM lower("title") OR "copy_$sort" IS NULL) | <>
              ~s|FROM "hologram_data"."my_app_task"|
          )

        assert total == 1005
        assert wrong == 0

        assert_keys("copy")
      end)
    end

    # The rows are read in id order, and the one the fn raises on holds the largest id a random
    # uuid can take, so it comes on the second page, after the first page is written. Its fixed
    # value is past the key cap, so the retry writes a search key too.
    test "keeps nothing of a fill whose fn raises on a later page, and applies on a retry", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      last_id = "ffffffff-ffff-4fff-bfff-ffffffffffff"

      value =
        elixir_fn(
          ~s|fn code -> if code == "bad", do: raise("bad code"), else: String.upcase(code) end|
        )

      route(scratch, fn ->
        assert run([create], first_model, @context) == :ok

        {:ok, _result} =
          Connection.query(
            ~s|INSERT INTO "hologram_data"."my_app_task" ("id", "code", "created_at", | <>
              ~s|"server_created_at", "server_created_seq", | <>
              ~s|"server_updated_at", "server_updated_seq", "updated_at", "$revisions") | <>
              ~s|SELECT gen_random_uuid(), 'code ' \|\| n, now(), now(), 0, now(), 0, now(), | <>
              ~s|'{}' | <>
              ~s|FROM generate_series(1, 1004) AS n|
          )

        {:ok, _result} =
          Connection.query(
            ~s|INSERT INTO "hologram_data"."my_app_task" ("id", "code", "created_at", | <>
              ~s|"server_created_at", "server_created_seq", | <>
              ~s|"server_updated_at", "server_updated_seq", "updated_at", "$revisions") | <>
              ~s|VALUES ($1::text::uuid, 'bad', now(), now(), 0, now(), 0, now(), '{}')|,
            [last_id]
          )

        assert_error RuntimeError, ~r/raised on row #{last_id}: .*bad code/s, fn ->
          apply_file([tighten_title(value)], create, first_model)
        end

        {:ok, %{rows: [[filled]]}} =
          Connection.query(
            ~s|SELECT COUNT(*) FROM "hologram_data"."my_app_task" WHERE "title" IS NOT NULL|
          )

        assert filled == 0
        assert nullable?("title")
        assert applied_versions() == MapSet.new(["20260813091522"])

        {:ok, _result} =
          Connection.query(
            ~s|UPDATE "hologram_data"."my_app_task" SET "code" = repeat('fixed ', 20) | <>
              ~s|WHERE "id" = $1::text::uuid|,
            [last_id]
          )

        assert apply_file([tighten_title(value)], create, first_model) == :ok

        {:ok, %{rows: rows}} =
          Connection.query(~s|SELECT "code", "title" FROM "hologram_data"."my_app_task"|)

        assert length(rows) == 1005
        assert Enum.all?(rows, fn [code, title] -> title == String.upcase(code) end)
        assert_keys("title")
        refute nullable?("title")
        assert applied_versions() == MapSet.new(["20260813091522", "20260813142237"])
      end)
    end

    test "reads several fields, decoded", %{scratch: scratch} = context do
      value = elixir_fn(~s|fn code, rank -> code <> ":" <> Integer.to_string(rank) end|)

      rows = fn -> insert_row("my_app_task", code: "a", rank: 5) end

      apply_scenario(context, rows, [add_filled(:label, :string, value, optional: true)])

      route(scratch, fn ->
        assert rows_by_code(["label"]) == [["a:5"]]
      end)
    end

    test "names the row when the function raises", context do
      value = elixir_fn("fn title -> String.upcase(title) end")
      rows = fn -> insert_row("my_app_task", code: "a") end

      assert_row_fill_refused(
        context,
        rows,
        [add_filled(:copy, :string, value, optional: true)],
        ~r/column "copy" on table "my_app_task" \(line 3\) raised on row [0-9a-f-]{36}: .*FunctionClauseError/s
      )
    end

    test "names the row when the fn throws a value whose calendar throws while printing it",
         context do
      value =
        elixir_fn("""
        fn title ->
          throw(%{
            __struct__: DateTime,
            calendar: Hologram.Test.Fixtures.Migration.Module2,
            year: String.length(title),
            month: 1,
            day: 1,
            hour: 0,
            minute: 0,
            second: 0,
            microsecond: {0, 0},
            time_zone: "Etc/UTC",
            zone_abbr: "UTC",
            utc_offset: 0,
            std_offset: 0
          })
        end
        """)

      rows = fn -> insert_row("my_app_task", code: "a", title: "abc") end

      assert_row_fill_refused(
        context,
        rows,
        [add_filled(:copy, :string, value, optional: true)],
        ~r/raised on row [0-9a-f-]{36}: \*\* \(throw\) %\{.*year: 3/s
      )
    end

    test "refuses a result of the wrong type, naming the row", context do
      value = elixir_fn("fn title -> String.length(title) end")
      rows = fn -> insert_row("my_app_task", code: "a", title: "abc") end

      assert_row_fill_refused(
        context,
        rows,
        [add_filled(:copy, :string, value, optional: true)],
        ~r/returned 3 for row [0-9a-f-]{36}, which isn't a value of type :string/
      )
    end

    test "refuses a result whose calendar throws while printing it, naming the row", context do
      value =
        elixir_fn("""
        fn title ->
          %{
            __struct__: DateTime,
            calendar: Hologram.Test.Fixtures.Migration.Module2,
            year: 9_997 + String.length(title),
            month: 1,
            day: 1,
            hour: 0,
            minute: 0,
            second: 0,
            microsecond: {0, 0},
            time_zone: "Etc/UTC",
            zone_abbr: "UTC",
            utc_offset: 0,
            std_offset: 0
          }
        end
        """)

      rows = fn -> insert_row("my_app_task", code: "a", title: "abc") end

      assert_row_fill_refused(
        context,
        rows,
        [add_filled(:due, :datetime, value, optional: true)],
        ~r/returned %\{.*\} for row [0-9a-f-]{36}, which isn't a value of type :datetime/s
      )
    end

    test "refuses nil on a required attribute", context do
      term = elixir_fn(~s|fn title -> if title == "x", do: title end|)
      rows = fn -> insert_row("my_app_task", code: "a", title: "abc") end

      assert_row_fill_refused(
        context,
        rows,
        [add_filled(:copy, :string, term)],
        ~r/leaves 1 row without a value - return a value from the fn for them, or make the attribute optional: true$/
      )
    end

    test "fills only the rows holding nil on a tightening", %{scratch: scratch} = context do
      rows = fn ->
        insert_row("my_app_task", [{"code", "a"}, {"title", "kept"}, {"title_$sort", "kept-key"}])
        insert_row("my_app_task", code: "b")
      end

      value = elixir_fn("fn code -> String.upcase(code) end")

      apply_scenario(context, rows, [tighten_title(value)])

      route(scratch, fn ->
        assert rows_by_code(["title", "title_$sort"]) ==
                 [["kept", "kept-key"], ["B", SortKey.compute("B")]]
      end)
    end

    test "refuses nil on a tightening", context do
      value = elixir_fn(~s|fn code -> if code == "x", do: code end|)
      rows = fn -> insert_row("my_app_task", code: "a") end

      assert_row_fill_refused(
        context,
        rows,
        [tighten_title(value)],
        ~r/leaves 1 row without a value - return a value from the fn for them, or keep optional: true on the attribute in the entity type and remove optional: false and backfill: from the op, or the whole op when it changes nothing else$/
      )
    end

    test "refuses a unique value repeating, naming the key and the rows", context do
      value = elixir_fn("fn title -> String.upcase(title) end")

      rows = fn ->
        insert_row("my_app_task", code: "a", title: "same")
        insert_row("my_app_task", code: "b", title: "same")
      end

      op = %{
        op: :change_attribute,
        entity: MyApp.Task,
        name: :slug,
        changes: [optional: false, backfill: value],
        line: 3
      }

      assert_row_fill_refused(
        context,
        rows,
        [op],
        ~r/repeats the key "SAME" of a unique index, on rows including [0-9a-f-]{36}/
      )
    end

    test "names a repeated key holding a newline", context do
      value = elixir_fn(~S|fn code -> String.replace(code, "-", "\n") end|)

      rows = fn ->
        insert_row("my_app_task", code: "x-y", title: "a")
        insert_row("my_app_task", code: "x-y", title: "b")
      end

      op = %{
        op: :change_attribute,
        entity: MyApp.Task,
        name: :slug,
        changes: [optional: false, backfill: value],
        line: 3
      }

      assert_row_fill_refused(
        context,
        rows,
        [op],
        ~r/repeats the key "x\\ny" of a unique index, on rows including [0-9a-f-]{36}/
      )
    end

    test "names the page when a value only looks like a key over several columns", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      keyed =
        migration("20260813100000", [
          %{op: :add_unique, entity: MyApp.Task, fields: [:title, :rank], line: 2}
        ])

      keyed_model = Model.fold(first_model, keyed.ops)
      value = elixir_fn("fn code -> String.trim(code) end")

      tighten =
        migration("20260813142237", [
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :title,
            changes: [optional: false, backfill: value],
            line: 3
          }
        ])

      route(scratch, fn ->
        assert run([create, keyed], keyed_model, @context) == :ok

        insert_row("my_app_task", code: "X", rank: 7)
        insert_row("my_app_task", code: "X", rank: 7)
        insert_row("my_app_task", code: "X, 7", rank: 1)

        assert_error RuntimeError, ~r/in the page of rows from /, fn ->
          run([create, keyed, tighten], Model.fold(keyed_model, tighten.ops), @context)
        end
      end)
    end

    test "names the page for a repeated key that isn't one column's text", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      key = %{op: :add_unique, entity: MyApp.Task, fields: [:title, :rank], line: 2}
      keyed = migration("20260813100000", [key])
      keyed_model = Model.fold(first_model, keyed.ops)
      value = elixir_fn("fn code -> String.upcase(String.first(code)) end")

      op = %{
        op: :change_attribute,
        entity: MyApp.Task,
        name: :title,
        changes: [optional: false, backfill: value],
        line: 3
      }

      tighten = migration("20260813142237", [op])

      route(scratch, fn ->
        assert run([create, keyed], keyed_model, @context) == :ok

        insert_row("my_app_task", code: "a1", rank: 7)
        insert_row("my_app_task", code: "a2", rank: 7)

        assert_error RuntimeError,
                     ~r/in the page of rows from [0-9a-f-]{36} to [0-9a-f-]{36}/,
                     fn ->
                       run(
                         [create, keyed, tighten],
                         Model.fold(keyed_model, tighten.ops),
                         @context
                       )
                     end
      end)
    end

    test "fills a relationship with an id from the row", %{scratch: scratch} = context do
      creator = Ecto.UUID.generate()

      rows = fn ->
        {:ok, _result} =
          Connection.query(
            ~s|INSERT INTO "hologram_data"."my_app_user" ("id", "created_at", | <>
              ~s|"server_created_at", "server_created_seq", | <>
              ~s|"server_updated_at", "server_updated_seq", "updated_at", "$revisions") | <>
              ~s|VALUES ($1::text::uuid, now(), now(), 0, now(), 0, now(), '{}')|,
            [creator]
          )

        insert_row("my_app_task", code: "a", creator_id: Ecto.UUID.dump!(creator))
      end

      value = elixir_fn("fn creator_id -> String.upcase(creator_id) end")

      op = %{
        op: :add_relationship,
        entity: MyApp.Task,
        name: :owner,
        type: MyApp.User,
        opts: [backfill: value],
        line: 3
      }

      apply_scenario(context, rows, [op])

      route(scratch, fn ->
        {:ok, %{rows: [[owner]]}} =
          Connection.query(~s|SELECT "owner_id"::text FROM "hologram_data"."my_app_task"|)

        assert owner == creator
      end)
    end

    test "refuses an id no row holds, naming the row", context do
      missing = "018f0000-0000-7000-8000-00000000dead"
      value = elixir_fn(~s|fn code -> code <> "018f0000-0000-7000-8000-00000000dead" end|)
      rows = fn -> insert_row("my_app_task", code: "") end

      op = %{
        op: :add_relationship,
        entity: MyApp.Task,
        name: :owner,
        type: MyApp.User,
        opts: [optional: true, backfill: value],
        line: 3
      }

      assert_row_fill_refused(
        context,
        rows,
        [op],
        ~r/writes #{missing} on row [0-9a-f-]{36}, which no MyApp.User holds/
      )
    end

    test "logs how many rows it filled", %{scratch: scratch} = context do
      value = elixir_fn("fn title -> String.upcase(title) end")
      rows = fn -> insert_row("my_app_task", code: "a", title: "x") end

      level = Logger.level()
      Logger.configure(level: :info)

      log =
        try do
          ExUnit.CaptureLog.capture_log([level: :info], fn ->
            apply_scenario(context, rows, [add_filled(:copy, :string, value, optional: true)])
          end)
        after
          Logger.configure(level: level)
        end

      assert log =~ ~s(filled 1 rows of column "copy" on table "my_app_task" row by row)

      route(scratch, fn ->
        assert rows_by_code(["copy"]) == [["X"]]
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

    test "refuses a value under a bound whose calendar throws while printing it", context do
      add_due = %{
        op: :add_attribute,
        entity: MyApp.Task,
        name: :due,
        type: :datetime,
        opts: [optional: true, backfill: ~U[2000-01-01 00:00:00Z]],
        line: 2
      }

      bound = %{~U[2020-01-01 00:00:00Z] | calendar: Hologram.Test.Fixtures.Migration.Module2}
      op = computed_add(:copy, :datetime, {:name, [:due]}, optional: true, min: bound)

      assert_fill_refused(context, ["one"], [add_due, op], ~r/must be at least %\{.*\(1 row\)/s)
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
