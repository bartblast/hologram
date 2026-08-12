defmodule Hologram.Migration.LoaderTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Migration.Loader

  alias Hologram.Reflection

  @tmp_dir Path.join([Reflection.tmp_dir(), "tests", "migration", "loader"])

  defp write_migrations!(test_dir, files) do
    dir = Path.join(@tmp_dir, test_dir)

    File.rm_rf!(dir)
    File.mkdir_p!(dir)

    Enum.each(files, fn {file_name, contents} ->
      dir
      |> Path.join(file_name)
      |> File.write!(contents)
    end)

    dir
  end

  describe "load_dir!/1" do
    test "returns the migrations ordered by version" do
      dir =
        write_migrations!("ordered", [
          {"20260813120000.exs", "use Hologram.Migration\n\ndelete_entity MyApp.Archive\n"},
          {"20260813090000.exs", "use Hologram.Migration\n\ncreate_entity MyApp.Task\n"}
        ])

      assert [first, second] = load_dir!(dir)

      assert first == %{
               version: "20260813090000",
               path: Path.join(dir, "20260813090000.exs"),
               ops: [%{op: :create_entity, entity: MyApp.Task, line: 3}]
             }

      assert second == %{
               version: "20260813120000",
               path: Path.join(dir, "20260813120000.exs"),
               ops: [%{op: :delete_entity, entity: MyApp.Archive, line: 3}]
             }
    end

    test "returns an empty list for an empty directory" do
      assert load_dir!(write_migrations!("empty", [])) == []
    end

    test "returns an empty list for a directory that does not exist" do
      assert load_dir!(Path.join(@tmp_dir, "nonexistent")) == []
    end

    test "rejects a file whose name is not a version" do
      dir =
        write_migrations!("invalid_name", [
          {"20260813090000_add_priority.exs", "use Hologram.Migration\n"}
        ])

      expected_msg =
        "invalid migration file name #{Path.join(dir, "20260813090000_add_priority.exs")} - " <>
          "a migration file is named after its version: 14 timestamp digits with the " <>
          "\".exs\" extension, e.g. \"20260813091500.exs\""

      assert_error Hologram.CompileError, expected_msg, fn ->
        load_dir!(dir)
      end
    end
  end

  describe "load_string!/2" do
    test "returns the ops of a file holding flat statements" do
      contents = """
      use Hologram.Migration

      rename_entity MyApp.Draft, MyApp.Sketch
      delete_entity MyApp.Archive
      """

      assert [rename_op, delete_op] = load_string!(contents, "20260813000000.exs")

      assert rename_op == %{
               op: :rename_entity,
               from: MyApp.Draft,
               to: MyApp.Sketch,
               line: 3
             }

      assert delete_op == %{op: :delete_entity, entity: MyApp.Archive, line: 4}
    end

    test "flattens entity blocks into the op list" do
      contents = """
      use Hologram.Migration

      change_entity MyApp.Task do
        rename_attribute :name, :title
        add_attribute :priority, :integer, backfill: 0
      end

      create_entity MyApp.Comment do
        add_attribute :body, :string
      end
      """

      assert [rename_op, add_op, create_op, body_op] =
               load_string!(contents, "20260813000000.exs")

      assert rename_op == %{
               op: :rename_attribute,
               entity: MyApp.Task,
               from: :name,
               to: :title,
               line: 4
             }

      assert add_op == %{
               op: :add_attribute,
               entity: MyApp.Task,
               name: :priority,
               type: :integer,
               opts: [backfill: 0],
               line: 5
             }

      assert create_op == %{op: :create_entity, entity: MyApp.Comment, line: 8}

      assert body_op == %{
               op: :add_attribute,
               entity: MyApp.Comment,
               name: :body,
               type: :string,
               opts: [],
               line: 9
             }
    end

    test "returns an empty list for a file holding only the header" do
      assert load_string!("use Hologram.Migration\n", "20260813000000.exs") == []
    end

    test "rejects a file without the header" do
      contents = """
      delete_entity MyApp.Archive
      """

      expected_msg =
        "migration file 20260813000000.exs must start with the use Hologram.Migration header"

      assert_error Hologram.CompileError, expected_msg, fn ->
        load_string!(contents, "20260813000000.exs")
      end
    end

    test "rejects an imperative statement naming its line" do
      contents = """
      use Hologram.Migration

      delete_entity MyApp.Archive

      for name <- [:a, :b] do
        delete_entity name
      end
      """

      expected_msg = "migration files contain only migration ops - 20260813000000.exs:5"

      assert_error Hologram.CompileError, expected_msg, fn ->
        load_string!(contents, "20260813000000.exs")
      end
    end

    test "rejects an unknown op naming its line" do
      contents = """
      use Hologram.Migration

      drop_entity MyApp.Archive
      """

      expected_msg = "migration files contain only migration ops - 20260813000000.exs:3"

      assert_error Hologram.CompileError, expected_msg, fn ->
        load_string!(contents, "20260813000000.exs")
      end
    end
  end

  describe "unresolved/1" do
    test "returns the resolve! ops" do
      contents = """
      use Hologram.Migration

      change_entity MyApp.Task do
        add_attribute :priority, :integer, backfill: 0
        resolve! :attributes, deleted: [:name], added: [:title]
      end
      """

      ops = load_string!(contents, "20260813000000.exs")

      assert unresolved(ops) == [
               %{
                 op: :resolve!,
                 entity: MyApp.Task,
                 kind: :attributes,
                 payload: [deleted: [:name], added: [:title]],
                 line: 5
               }
             ]
    end

    test "returns an empty list when no op demands resolution" do
      assert unresolved([%{op: :delete_entity, entity: MyApp.Archive, line: 3}]) == []
    end
  end
end
