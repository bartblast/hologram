defmodule Hologram.Migration.LoaderTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Migration.Loader

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
