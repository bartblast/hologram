defmodule Hologram.Entity.ExpressionTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Entity.Expression

  # The code is parsed at line 12 of a relationship line written at line 7, so a refusal located at
  # a node names line 12 and one located at a node carrying no line (a literal) names the line's.
  defp env do
    %{__ENV__ | file: Path.join(File.cwd!(), "lib/my_app/channel.ex"), line: 7}
  end

  # Parses the options of a relationship line, lowers them and evaluates what they lowered to in
  # this module, with the given binding standing for the caller's variables.
  defp lower_opts(code, binding \\ []) do
    {value, _binding} =
      code
      |> Code.string_to_quoted!(line: 12)
      |> relationship_opts(env_binding(Keyword.keys(binding)))
      |> Code.eval_quoted(binding, env())

    value
  end

  # Parses the argument of a unique line, lowers it and evaluates what it lowered to in this
  # module, with the given binding standing for the caller's variables.
  defp lower_unique(code, binding \\ []) do
    {value, _binding} =
      code
      |> Code.string_to_quoted!(line: 12)
      |> unique_fields(env_binding(Keyword.keys(binding)))
      |> Code.eval_quoted(binding, env())

    value
  end

  # The env of a line written where variables of the given names are bound, as a pinned name reads
  # one.
  defp env_binding(names) do
    assignments = Enum.map(names, &{:=, [], [{&1, [], nil}, nil]})

    {_value, _binding, env} =
      Code.eval_quoted_with_env({:__block__, [], [nil | assignments]}, [], env())

    env
  end

  describe "relationship_opts/2" do
    test "lowers a bare inverse name to an atom" do
      assert lower_opts("[inverse: channel]") == [inverse: :channel]
    end

    test "lowers a pinned inverse name to its value" do
      assert lower_opts("[inverse: ^name]", name: :channel) == [inverse: :channel]
    end

    test "lowers a bare sort name to an atom" do
      assert lower_opts("[inverse: channel, sort: position]") == [
               inverse: :channel,
               sort: :position
             ]
    end

    test "lowers a sort list of names and directions" do
      assert lower_opts("[inverse: channel, sort: [position, created_at: :desc]]") == [
               inverse: :channel,
               sort: [:position, created_at: :desc]
             ]
    end

    test "lowers a pinned sort to its value" do
      assert lower_opts("[inverse: channel, sort: ^spec]", spec: [position: :desc]) == [
               inverse: :channel,
               sort: [position: :desc]
             ]
    end

    test "keeps every other option as written" do
      assert lower_opts("[optional: flag, unique: true]", flag: true) == [
               optional: true,
               unique: true
             ]
    end

    test "keeps options not written as a list in place" do
      assert lower_opts("opts", opts: [optional: true]) == [optional: true]
    end

    test "lowers a sort list of bare names" do
      assert lower_opts("[inverse: channel, sort: [position, title]]") == [
               inverse: :channel,
               sort: [:position, :title]
             ]
    end

    test "keeps a non-keyword element for the declaration to refuse" do
      assert lower_opts("[:optional]") == [:optional]
    end

    test "raises on an inverse written as an atom" do
      assert_error Hologram.CompileError,
                   "lib/my_app/channel.ex:7: inverse names the relationship it reverses with a bare name, got: :channel - write channel",
                   fn -> lower_opts("[inverse: :channel]") end
    end

    test "raises on an inverse that is not a name" do
      assert_error Hologram.CompileError,
                   "lib/my_app/channel.ex:12: inverse names the relationship it reverses with a bare name, or with a pinned expression when the name comes from the surrounding code, got: channel.org - a value from the surrounding code is pinned: ^channel.org",
                   fn -> lower_opts("[inverse: channel.org]") end
    end

    test "raises on an inverse naming the module" do
      assert_error Hologram.CompileError,
                   "lib/my_app/channel.ex:12: inverse names the relationship it reverses with a bare name, or with a pinned expression when the name comes from the surrounding code, got: __MODULE__",
                   fn -> lower_opts("[inverse: __MODULE__]") end
    end

    test "raises on options not written in place that hold inverse or sort" do
      assert_error Hologram.CompileError,
                   "relationship options with inverse: or sort: are written in place on the line, got: [inverse: :channel]",
                   fn -> lower_opts("opts", opts: [inverse: :channel]) end

      assert_error Hologram.CompileError,
                   "relationship options with inverse: or sort: are written in place on the line, got: [sort: :position]",
                   fn -> lower_opts("opts", opts: [sort: :position]) end
    end

    test "raises on a pinned inverse name no variable holds, naming the bare name" do
      assert_error Hologram.CompileError,
                   "lib/my_app/channel.ex:12: ^channel pins channel, which no variable holds here - inverse names the relationship it reverses with a bare name, without the pin: channel",
                   fn -> lower_opts("[inverse: ^channel]") end
    end

    test "raises on a pinned sort name no variable holds, naming the bare name" do
      assert_error Hologram.CompileError,
                   "lib/my_app/channel.ex:12: ^created_at pins created_at, which no variable holds here - sort names an attribute with a bare name, without the pin: created_at",
                   fn -> lower_opts("[sort: ^created_at]") end
    end

    test "raises on a sort name written as an atom" do
      assert_error Hologram.CompileError,
                   "lib/my_app/channel.ex:7: sort names an attribute with a bare name, got: :position - write position",
                   fn -> lower_opts("[inverse: channel, sort: :position]") end
    end
  end

  describe "unique_fields/2" do
    test "lowers a list of bare names to atoms" do
      assert lower_unique("[workspace, slug]") == [:workspace, :slug]
    end

    test "lowers a pinned list to its value" do
      assert lower_unique("^fields", fields: [:workspace, :slug]) == [:workspace, :slug]
    end

    test "lowers a pinned element to its value" do
      assert lower_unique("[workspace, ^field]", field: :slug) == [:workspace, :slug]
    end

    test "keeps nil for the declaration to refuse" do
      assert lower_unique("nil") == nil
    end

    test "raises on a field written as an atom" do
      assert_error Hologram.CompileError,
                   "lib/my_app/channel.ex:7: unique names a field with a bare name, got: :workspace - write workspace",
                   fn -> lower_unique("[:workspace, :slug]") end
    end

    test "raises on a pinned element no variable holds, naming the bare name" do
      assert_error Hologram.CompileError,
                   "lib/my_app/channel.ex:12: ^slug pins slug, which no variable holds here - unique names a field with a bare name, without the pin: slug",
                   fn -> lower_unique("[workspace, ^slug]") end
    end

    test "raises on a pinned bare name no variable holds" do
      assert_error Hologram.CompileError,
                   "lib/my_app/channel.ex:12: ^fields pins fields, which no variable holds here - unique names fields with bare names in a list, like unique [workspace, slug]",
                   fn -> lower_unique("^fields") end
    end

    test "raises on a lone bare name, naming the option a single field is unique through" do
      assert_error Hologram.CompileError,
                   "lib/my_app/channel.ex:12: unique takes a list of fields written in place, or a pinned expression when the list comes from the surrounding code, got: slug - a single field is unique through its own option, unique: true on the attribute or the relationship",
                   fn -> lower_unique("slug") end
    end

    test "raises on a lone atom, naming the option a single field is unique through" do
      assert_error Hologram.CompileError,
                   "lib/my_app/channel.ex:7: unique takes a list of fields written in place, or a pinned expression when the list comes from the surrounding code, got: :slug - a single field is unique through its own option, unique: true on the attribute or the relationship",
                   fn -> lower_unique(":slug") end
    end

    test "raises on a lone variable, naming the pin" do
      assert_error Hologram.CompileError,
                   "lib/my_app/channel.ex:12: unique takes a list of fields written in place, or a pinned expression when the list comes from the surrounding code, got: fields - write ^fields",
                   fn -> lower_unique("fields", fields: [:workspace, :slug]) end
    end

    test "raises on an unpinned module attribute" do
      assert_error Hologram.CompileError,
                   "lib/my_app/channel.ex:12: unique takes a list of fields written in place, or a pinned expression when the list comes from the surrounding code, got: @fields",
                   fn -> lower_unique("@fields") end
    end

    test "raises on a string in the list" do
      assert_error Hologram.CompileError,
                   ~s(lib/my_app/channel.ex:7: unique names a field with a bare name, or with a pinned expression when the name comes from the surrounding code, got: "title"),
                   fn -> lower_unique(~s([slug, "title"])) end
    end

    test "raises on an improper list" do
      assert_error Hologram.CompileError,
                   "lib/my_app/channel.ex:12: unique names a field with a bare name, or with a pinned expression when the name comes from the surrounding code, got: :slug | :title - a value from the surrounding code is pinned: ^(:slug | :title)",
                   fn -> lower_unique("[:slug | :title]") end
    end

    test "raises on the module in the list" do
      assert_error Hologram.CompileError,
                   "lib/my_app/channel.ex:12: unique names a field with a bare name, or with a pinned expression when the name comes from the surrounding code, got: __MODULE__",
                   fn -> lower_unique("[__MODULE__, slug]") end
    end
  end
end
