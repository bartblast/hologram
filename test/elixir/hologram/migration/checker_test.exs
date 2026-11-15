defmodule Hologram.Migration.CheckerTest do
  # async: false - the green path shadow-verifies against the scratch database, a
  # per-suite singleton (the configured name + "_shadow").
  #
  # The tests tagged :database are the ones that shadow-verify: the verifier opens its own
  # connection to the server, so they need one, whatever the suite booted.
  use Hologram.Test.BasicCase, async: false

  import Hologram.Migration.Checker

  alias Hologram.Migration.Loader

  defp history(files) do
    files
    |> Enum.map(fn {version, body} -> compile_migration(version, body) end)
    |> Loader.from_modules!()
  end

  defp model(entities) do
    entries =
      Map.new(entities, fn {entity_type, entry_overrides} ->
        entry = Map.merge(%{attributes: [], relationships: [], roles: []}, entry_overrides)

        {entity_type, entry}
      end)

    %{entities: entries, roles: %{}, user_entity: nil}
  end

  describe "check!/2" do
    @tag :database
    test "passes a resolved history producing the model" do
      contents = """
      create_entity MyApp.Task do
        add_attribute :title, :string
      end
      """

      migrations = history([{"20260813091522", contents}])
      current = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      assert check!(migrations, current) == :ok
    end

    test "refuses a draft still holding resolve! ops" do
      contents = """
      change_entity MyApp.Task do
        resolve! :attributes, deleted: [:name], added: [:title]
      end
      """

      migrations = history([{"20260813091522", contents}])
      current = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      expected_msg =
        normalize_newlines("""
        the migration draft is not resolved yet:
          app/migrations/20260813091522.ex:5 - :attributes
        Write the ops that express what happened, delete the resolve! lines, then finalize with mix holo.gen.migration.\
        """)

      assert_error RuntimeError, expected_msg, fn -> check!(migrations, current) end
    end

    test "refuses a history not covering the model" do
      contents = """
      create_entity MyApp.Task do
        add_attribute :name, :string
      end
      """

      migrations = history([{"20260813091522", contents}])
      current = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      expected_msg =
        "migration history does not produce this model - " <>
          "1 model change has no migration (MyApp.Task) - run mix holo.gen.migration"

      assert_error RuntimeError, expected_msg, fn -> check!(migrations, current) end
    end

    @tag :database
    test "refuses a history that cannot build the model's schema" do
      create_contents = """
      create_entity MyApp.Tag

      create_entity MyApp.Task do
        add_relationship :tags, [MyApp.Tag]
      end
      """

      narrow_contents = """
      change_entity MyApp.Task do
        change_relationship :tags, type: MyApp.Tag
      end
      """

      migrations =
        history([{"20260813091522", create_contents}, {"20260813091523", narrow_contents}])

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

      assert_error Hologram.CompileError, expected_msg, fn ->
        check!(migrations, current)
      end
    end
  end
end
