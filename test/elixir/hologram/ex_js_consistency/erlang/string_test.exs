defmodule Hologram.ExJsConsistency.Erlang.StringTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/binary_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "titlecase/1" do
    test "empty string" do
      assert :string.titlecase("") == ""
    end

    test "capitalizes hologram" do
      assert :string.titlecase("hologram") == "Hologram"
    end

    test "capitalizes hologram once" do
      assert :string.titlecase("hologram hologram") == "Hologram hologram"
    end

    test "raises on int" do
      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":string.titlecase/1", [1], []),
                   fn -> :string.titlecase(1) end
    end

    test "ß" do
      assert :string.titlecase("ß") == "Ss"
    end

    test "emoji" do
      [
        {"👩‍👩‍👦‍👦", "👩‍👩‍👦‍👦"},
        {"👩‍🚒", "👩‍🚒"}
      ]
      |> Enum.each(fn {input, expected} ->
        assert :string.titlecase(input) == expected
      end)
    end

    test "empty charlist" do
      assert :string.titlecase([]) == []
    end

    test "charlist" do
      assert :string.titlecase([97, 98, 99]) == [65, 98, 99]
    end

    test "list of charlist" do
      assert :string.titlecase([[97], [97]]) == [65, 97]
    end

    test "list of list of charlist" do
      assert :string.titlecase([[[97], [97]], [97]]) == [65, 97, 97]
    end
  end
end
