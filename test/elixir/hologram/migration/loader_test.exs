defmodule Hologram.Migration.LoaderTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Migration.Loader

  alias Hologram.Reflection

  defp write_migrations_dir_file!(app_dir, file_name) do
    dir = Path.join([app_dir, "app", "migrations"])

    File.mkdir_p!(dir)

    dir
    |> Path.join(file_name)
    |> File.write!("")
  end

  describe "from_modules!/1" do
    test "returns the migrations of the given modules ordered by version" do
      later = compile_migration("20260813142237", "delete_entity MyApp.Archive")
      earlier = compile_migration("20260813091522", "create_entity MyApp.Task")

      assert from_modules!([later, earlier]) == [
               %{
                 version: "20260813091522",
                 path: "app/migrations/20260813091522.ex",
                 ops: [%{op: :create_entity, entity: MyApp.Task, line: 4}],
                 module: earlier
               },
               %{
                 version: "20260813142237",
                 path: "app/migrations/20260813142237.ex",
                 ops: [%{op: :delete_entity, entity: MyApp.Archive, line: 4}],
                 module: later
               }
             ]
    end

    test "returns an empty list for no modules" do
      assert from_modules!([]) == []
    end

    test "rejects two modules defining the same version" do
      first = compile_migration("20260813091522", "create_entity MyApp.Task")
      second = compile_migration("20260813091522", "delete_entity MyApp.Archive")

      expected_msg =
        "migration version 20260813091522 is defined twice - " <>
          "#{inspect(first)} (app/migrations/20260813091522.ex) and " <>
          "#{inspect(second)} (app/migrations/20260813091522.ex)"

      assert_error Hologram.CompileError, expected_msg, fn ->
        from_modules!([first, second])
      end
    end
  end

  describe "list!/0" do
    test "returns an empty list for the project, which defines no migration" do
      assert list!() == []
    end
  end

  describe "migrations_dir!/0" do
    test "refuses a project that does not compile app/migrations/" do
      expected_msg =
        "the project does not compile app/migrations/, where migration modules live - " <>
          "add \"app\" to elixirc_paths in mix.exs"

      assert_error RuntimeError, expected_msg, fn -> migrations_dir!() end
    end
  end

  describe "unresolved/1" do
    test "returns the resolve! ops" do
      resolve_op = %{
        op: :resolve!,
        entity: MyApp.Task,
        kind: :attributes,
        payload: [deleted: [:name], added: [:title]],
        line: 5
      }

      ops = [
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :priority,
          type: :integer,
          opts: [backfill: 0],
          line: 4
        },
        resolve_op
      ]

      assert unresolved(ops) == [resolve_op]
    end

    test "returns an empty list when no op demands resolution" do
      assert unresolved([%{op: :delete_entity, entity: MyApp.Archive, line: 3}]) == []
    end
  end

  describe "unresolved_entries/1" do
    test "returns the resolve! ops of the migrations with their paths, in history order" do
      first_op = %{op: :resolve!, kind: :entities, payload: [], line: 4}
      second_op = %{op: :resolve!, entity: MyApp.Task, kind: :fill, payload: [], line: 5}

      migrations = [
        %{
          version: "20260813091522",
          path: "app/migrations/20260813091522.ex",
          ops: [%{op: :create_entity, entity: MyApp.Task, line: 4}]
        },
        %{version: "20260813142237", path: "app/migrations/20260813142237.ex", ops: [first_op]},
        %{version: "20260814080000", path: "app/migrations/20260814080000.ex", ops: [second_op]}
      ]

      assert unresolved_entries(migrations) == [
               {"app/migrations/20260813142237.ex", first_op},
               {"app/migrations/20260814080000.ex", second_op}
             ]
    end
  end

  describe "unresolved_lines/1" do
    test "returns one line per entry with its location and kind" do
      entries = [
        {"app/migrations/20260813142237.ex", %{op: :resolve!, kind: :entities, line: 4}},
        {"app/migrations/20260814080000.ex", %{op: :resolve!, kind: :fill, line: 5}}
      ]

      assert unresolved_lines(entries) ==
               "  app/migrations/20260813142237.ex:4 - :entities\n" <>
                 "  app/migrations/20260814080000.ex:5 - :fill"
    end
  end

  describe "validate_resolved!/2" do
    setup do
      [
        migrations: [
          %{
            version: "20260813091522",
            path: "app/migrations/20260813091522.ex",
            ops: [%{op: :create_entity, entity: MyApp.Task, line: 4}]
          },
          %{
            version: "20260813142237",
            path: "app/migrations/20260813142237.ex",
            ops: [%{op: :resolve!, kind: :entities, payload: [], line: 4}]
          }
        ]
      ]
    end

    test "refuses a draft in a prod build", %{migrations: migrations} do
      expected_msg =
        normalize_newlines("""
        the migration draft is not resolved yet, and a prod build refuses it:
          app/migrations/20260813142237.ex:4 - :entities
        Write the ops that express what happened, delete the resolve! lines, then finalize with mix holo.gen.migration.\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_resolved!(migrations, :prod)
      end
    end

    test "refuses a draft in any build but dev and test", %{migrations: migrations} do
      assert_raise Hologram.CompileError, ~r/a staging build refuses it/, fn ->
        validate_resolved!(migrations, :staging)
      end
    end

    test "accepts a draft in a dev build", %{migrations: migrations} do
      assert validate_resolved!(migrations, :dev) == :ok
    end

    test "accepts a draft in a test build", %{migrations: migrations} do
      assert validate_resolved!(migrations, :test) == :ok
    end

    test "accepts resolved migrations in a prod build", %{migrations: [resolved | _drafts]} do
      assert validate_resolved!([resolved], :prod) == :ok
    end
  end

  describe "validate_migrations_compiled!/2" do
    setup do
      app_dir =
        Path.join([Reflection.tmp_dir(), "tests", "migration", "loader", random_string()])

      on_exit(fn -> File.rm_rf!(app_dir) end)

      %{app_dir: app_dir}
    end

    test "refuses migration files the given elixirc_paths leave out", %{app_dir: app_dir} do
      write_migrations_dir_file!(app_dir, "20260813091522.ex")

      expected_msg =
        "app/migrations/ holds migration files, but this build does not compile the " <>
          "directory, so the app would ship without its migrations - add \"app\" to " <>
          "elixirc_paths in mix.exs, for every environment"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_migrations_compiled!(app_dir, ["lib"])
      end
    end

    test "passes migration files compiled through app/", %{app_dir: app_dir} do
      write_migrations_dir_file!(app_dir, "20260813091522.ex")

      assert validate_migrations_compiled!(app_dir, ["app", "lib"]) == :ok
    end

    test "passes migration files compiled through app/migrations/ itself", %{app_dir: app_dir} do
      write_migrations_dir_file!(app_dir, "20260813091522.ex")

      assert validate_migrations_compiled!(app_dir, ["app/migrations/", "lib"]) == :ok
    end

    test "passes a directory holding no migration file", %{app_dir: app_dir} do
      write_migrations_dir_file!(app_dir, ".gitkeep")

      assert validate_migrations_compiled!(app_dir, ["lib"]) == :ok
    end

    test "passes an app without the directory", %{app_dir: app_dir} do
      assert validate_migrations_compiled!(app_dir, ["lib"]) == :ok
    end
  end

  describe "validate_migrations_compiled!/1" do
    setup do
      app_dir =
        Path.join([Reflection.tmp_dir(), "tests", "migration", "loader", random_string()])

      on_exit(fn -> File.rm_rf!(app_dir) end)

      %{app_dir: app_dir}
    end

    test "refuses migration files the project's elixirc_paths leave out", %{app_dir: app_dir} do
      write_migrations_dir_file!(app_dir, "20260813091522.ex")

      assert_raise Hologram.CompileError, ~r/app\/migrations\/ holds migration files/, fn ->
        validate_migrations_compiled!(app_dir)
      end
    end

    test "passes the OTP app by default, whose app/migrations/ does not exist" do
      assert validate_migrations_compiled!() == :ok
    end
  end

  describe "verify_rename_order!/2" do
    test "passes a file whose rename precedes every reference to the renamed entity" do
      ops = [
        %{op: :rename_entity, from: MyApp.Draft, to: MyApp.Sketch, line: 3},
        %{
          op: :add_attribute,
          entity: MyApp.Sketch,
          name: :summary,
          type: :string,
          opts: [],
          line: 4
        },
        %{op: :delete_entity, entity: MyApp.Archive, line: 5}
      ]

      assert verify_rename_order!(ops, "app/migrations/20260813091522.ex") == :ok
    end

    test "passes a file without renames" do
      ops = [%{op: :delete_entity, entity: MyApp.Archive, line: 3}]

      assert verify_rename_order!(ops, "app/migrations/20260813091522.ex") == :ok
    end

    test "rejects an op scoped to the pre-rename name" do
      ops = [
        %{
          op: :add_attribute,
          entity: MyApp.Draft,
          name: :summary,
          type: :string,
          opts: [],
          line: 3
        },
        %{op: :rename_entity, from: MyApp.Draft, to: MyApp.Sketch, line: 4}
      ]

      expected_msg =
        "app/migrations/20260813091522.ex:3 references MyApp.Draft, renamed on line 4 - " <>
          "move the rename first and use MyApp.Sketch"

      assert_error Hologram.CompileError, expected_msg, fn ->
        verify_rename_order!(ops, "app/migrations/20260813091522.ex")
      end
    end

    test "rejects a designation naming the pre-rename name" do
      ops = [
        %{op: :rename_entity, from: MyApp.Draft, to: MyApp.Sketch, line: 3},
        %{op: :designate_user_entity, entity: MyApp.Draft, line: 4}
      ]

      expected_msg =
        "app/migrations/20260813091522.ex:4 references MyApp.Draft, renamed on line 3 - " <>
          "move the rename first and use MyApp.Sketch"

      assert_error Hologram.CompileError, expected_msg, fn ->
        verify_rename_order!(ops, "app/migrations/20260813091522.ex")
      end
    end

    test "rejects a relationship targeting the pre-rename name" do
      ops = [
        %{op: :rename_entity, from: MyApp.Draft, to: MyApp.Sketch, line: 3},
        %{
          op: :add_relationship,
          entity: MyApp.Task,
          name: :drafts,
          type: [MyApp.Draft],
          opts: [],
          line: 4
        }
      ]

      expected_msg =
        "app/migrations/20260813091522.ex:4 references MyApp.Draft, renamed on line 3 - " <>
          "move the rename first and use MyApp.Sketch"

      assert_error Hologram.CompileError, expected_msg, fn ->
        verify_rename_order!(ops, "app/migrations/20260813091522.ex")
      end
    end
  end
end
