defmodule Hologram.ExJsConsistency.Erlang.StringTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/string_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "join/2" do
    test "single element" do
      assert :string.join([~c"hello"], ~c", ") == ~c"hello"
    end

    test "multiple elements" do
      assert :string.join([~c"one", ~c"two", ~c"three"], ~c", ") == ~c"one, two, three"
    end

    test "empty separator" do
      assert :string.join([~c"hello", ~c"world"], ~c"") == ~c"helloworld"
    end

    test "empty strings (charlists) in list" do
      assert :string.join([~c"", ~c"hello", ~c"", ~c"world", ~c""], ~c"-") == ~c"-hello--world-"
    end

    test "multi-character separator" do
      assert :string.join([~c"apple", ~c"banana", ~c"cherry"], ~c" and ") == ~c"apple and banana and cherry"
    end

    test "empty list" do
      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":string.join/2", [[], ~c", "]),
                   fn ->
                     :string.join([], ~c", ")
                   end
    end

    test "first argument is not a list" do
      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":string.join/2", [:not_a_list, ~c", "]),
                   fn ->
                     :string.join(:not_a_list, ~c", ")
                   end
    end
  end
end
