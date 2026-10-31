defmodule Hologram.Entity.ExpressionTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Entity.Expression

  # The code is parsed at line 12 of a relationship line written at line 7, so a refusal located at
  # a node names line 12 and one located at a node carrying no line (a literal) names the line's.
  defp env do
    %{__ENV__ | file: Path.join(File.cwd!(), "lib/my_app/channel.ex"), line: 7}
  end

  # Parses the options of a relationship line, lowers them and evaluates what they lowered to in
  # this module, with the given binding standing for the caller's values.
  defp lower_opts(code, binding \\ []) do
    {value, _binding} =
      code
      |> Code.string_to_quoted!(line: 12)
      |> relationship_opts(env())
      |> Code.eval_quoted(binding, env())

    value
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

    test "raises on a sort name written as an atom" do
      assert_error Hologram.CompileError,
                   "lib/my_app/channel.ex:7: sort names an attribute with a bare name, got: :position - write position",
                   fn -> lower_opts("[inverse: channel, sort: :position]") end
    end
  end
end
