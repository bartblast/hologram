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

    test "bitstring" do
      assert :string.titlecase(<<104, 101, 108, 108, 111, 0>>) == <<72, 101, 108, 108, 111, 0>>
    end

    test "ß" do
      assert :string.titlecase("ß") == "Ss"
    end

    test "👩‍🚒" do
      assert :string.titlecase("👩‍🚒") == "👩‍🚒"
    end

    test "charlist" do
      assert :string.titlecase([97, 98, 99]) == [65, 98, 99]
    end

    test "empty charlist" do
      assert :string.titlecase([]) == []
    end
  end
end
