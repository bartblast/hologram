defmodule Hologram.Migration.CheckerTest do
  # async: false - the green path shadow-verifies against the scratch database, a
  # per-suite singleton (the configured name + "_shadow").
  use Hologram.Test.BasicCase, async: false

  import Hologram.Migration.Checker

  alias Hologram.Reflection

  @tmp_dir Path.join([Reflection.tmp_dir(), "tests", "migration", "checker"])

  defp migrations_dir!(test_dir, files) do
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

  defp model(entities) do
    entries =
      Map.new(entities, fn {entity_type, entry_overrides} ->
        entry = Map.merge(%{attributes: [], relationships: [], roles: []}, entry_overrides)

        {entity_type, entry}
      end)

    %{entities: entries, roles: %{}}
  end

  describe "check!/2" do
    test "passes a resolved history producing the model" do
      contents = """
      use Hologram.Migration

      create_entity MyApp.Task do
        add_attribute :title, :string
      end
      """

      dir = migrations_dir!("passes", [{"20260813091522.exs", contents}])
      current = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      assert check!(dir, current) == :ok
    end

    test "refuses a draft still holding resolve! ops" do
      contents = """
      use Hologram.Migration

      change_entity MyApp.Task do
        resolve! :attributes, deleted: [:name], added: [:title]
      end
      """

      dir = migrations_dir!("unresolved", [{"20260813091522.exs", contents}])
      current = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})
      path = Path.join(dir, "20260813091522.exs")

      expected_msg =
        normalize_newlines("""
        the migration draft is not resolved yet:
          #{path}:4 - :attributes
        Write the ops that express what happened, delete the resolve! lines, then finalize with mix holo.gen.migration.\
        """)

      assert_error RuntimeError, expected_msg, fn -> check!(dir, current) end
    end

    test "refuses a history not covering the model" do
      contents = """
      use Hologram.Migration

      create_entity MyApp.Task do
        add_attribute :name, :string
      end
      """

      dir = migrations_dir!("not_covered", [{"20260813091522.exs", contents}])
      current = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      expected_msg =
        "migration history does not produce this model - " <>
          "1 model change has no migration (MyApp.Task) - run mix holo.gen.migration"

      assert_error RuntimeError, expected_msg, fn -> check!(dir, current) end
    end

    test "refuses a history that cannot build the model's schema" do
      create_contents = """
      use Hologram.Migration

      create_entity MyApp.Tag

      create_entity MyApp.Task do
        add_relationship :tags, [MyApp.Tag]
      end
      """

      narrow_contents = """
      use Hologram.Migration

      change_entity MyApp.Task do
        change_relationship :tags, type: MyApp.Tag
      end
      """

      dir =
        migrations_dir!("narrowing", [
          {"20260813091522.exs", create_contents},
          {"20260813091523.exs", narrow_contents}
        ])

      current =
        model(%{
          MyApp.Tag => %{},
          MyApp.Task => %{relationships: [{:tags, MyApp.Tag, []}]}
        })

      expected_msg =
        "changing relationship :tags on MyApp.Task from to-many to to-one is not " <>
          "supported - a row holding several targets has no one target to keep - " <>
          "delete the relationship and add it with the new cardinality, or write " <>
          "the migration that picks the survivors"

      assert_error Hologram.CompileError, expected_msg, fn -> check!(dir, current) end
    end
  end
end
