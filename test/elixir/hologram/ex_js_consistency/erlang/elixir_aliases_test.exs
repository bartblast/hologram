defmodule Hologram.ExJsConsistency.Erlang.ElixirAliasesTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/elixir_aliases_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "concat/1" do
    test "works with atom segments which are Elixir module aliases" do
      assert :elixir_aliases.concat([Aaa, Bbb, Ccc]) == Aaa.Bbb.Ccc
    end

    test "works with atom segments which are not Elixir module aliases" do
      assert :elixir_aliases.concat([:Aaa, :Bbb, :Ccc]) == Aaa.Bbb.Ccc
    end

    test "works with binary bitstring segments" do
      assert :elixir_aliases.concat(["Aaa", "Bbb", "Ccc"]) == Aaa.Bbb.Ccc
    end

    test "ignores nil segments" do
      assert :elixir_aliases.concat([Aaa, nil, Ccc]) == Aaa.Ccc
    end

    test "removes the first dot character from the segment before joining segments with a dot character" do
      assert :elixir_aliases.concat(["...Aaa", "...Bbb", "...Ccc"]) == :"Elixir...Aaa...Bbb...Ccc"
    end

    test "doesn't prepend 'Elixir' segment if it is already present as the first element" do
      assert :elixir_aliases.concat(["Elixir", Aaa, Bbb, Ccc]) == Aaa.Bbb.Ccc
    end

    test "raises FunctionClauseError if the argument is not a list" do
      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":elixir_aliases.do_concat/2", [:abc, "Elixir"]),
                   fn -> :elixir_aliases.concat(:abc) end
    end

    test "raises FunctionClauseError if a non-binary bitstring segment is present" do
      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":elixir_aliases.do_concat/2", [
                     [<<1::size(2)>>, "Ccc"],
                     "Elixir.Aaa"
                   ]),
                   fn -> :elixir_aliases.concat(["Aaa", <<1::2>>, "Ccc"]) end
    end

    test "raises FunctionClauseError if any non-atom or non-bitstring segments are present" do
      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":elixir_aliases.do_concat/2", [
                     [123, "Ccc"],
                     "Elixir.Aaa"
                   ]),
                   fn ->
                     :elixir_aliases.concat(["Aaa", 123, "Ccc"])
                   end
    end

    test "raises FunctionClauseError if invalid segment is present and the segments contain 'Elixir' as the first segment" do
      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":elixir_aliases.do_concat/2", [
                     [123, "Ccc"],
                     "Elixir.Aaa"
                   ]),
                   fn ->
                     :elixir_aliases.concat(["Elixir", "Aaa", 123, "Ccc"])
                   end
    end

    test "raises FunctionClauseError if invalid segment is present as the first segment" do
      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":elixir_aliases.do_concat/2", [
                     [123, "Ccc"],
                     "Elixir"
                   ]),
                   fn ->
                     :elixir_aliases.concat([123, "Ccc"])
                   end
    end
  end
end
