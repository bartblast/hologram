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
      assert :string.join(['hello'], ', ') == 'hello'
    end

    test "multiple elements" do
      assert :string.join(['one', 'two', 'three'], ', ') == 'one, two, three'
    end

    test "empty separator" do
      assert :string.join(['hello', 'world'], '') == 'helloworld'
    end

    test "empty strings (charlists) in list" do
      assert :string.join(['', 'hello', '', 'world', ''], '-') == '-hello--world-'
    end

    test "multi-character separator" do
      assert :string.join(['apple', 'banana', 'cherry'], ' and ') == 'apple and banana and cherry'
    end

    test "empty list" do
      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":string.join/2", [[], ', ']),
                   fn ->
                     :string.join([], ', ')
                   end
    end

    test "first argument is not a list" do
      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":string.join/2", [:not_a_list, ', ']),
                   fn ->
                     :string.join(:not_a_list, ', ')
                   end
    end
  end
end
