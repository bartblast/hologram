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

    test "error frame carries the do_concat args for a non-list argument" do
      segments = wrap_term(:abc)

      top_frame =
        try do
          :elixir_aliases.concat(segments)
        rescue
          _error -> hd(wrap_term(__STACKTRACE__))
        end

      # The server implements this function in Erlang code inside
      # elixir_aliases.erl, so its frame location also carries the
      # Elixir-internal file and line, which the client doesn't mirror.
      assert {:elixir_aliases, :do_concat, [:abc, "Elixir"], location} = wrap_term(top_frame)
      assert location[:error_info] == nil
    end

    test "error frame carries the do_concat args for an invalid segment" do
      segments = wrap_term(["Aaa", "Bbb", 123])

      top_frame =
        try do
          :elixir_aliases.concat(segments)
        rescue
          _error -> hd(wrap_term(__STACKTRACE__))
        end

      # The server implements this function in Erlang code inside
      # elixir_aliases.erl, so its frame location also carries the
      # Elixir-internal file and line, which the client doesn't mirror.
      assert {:elixir_aliases, :do_concat, [[123], "Elixir.Aaa.Bbb"], location} =
               wrap_term(top_frame)

      assert location[:error_info] == nil
    end
  end

  # Note: there's no atom table limitation in the client-side Hologram runtime,
  # safe_concat/1 can simply delegate directly to concat/1 there.
  # Here we're just testing the function is available.
  test "safe_concat/1" do
    assert :elixir_aliases.safe_concat([Date, Range]) == Date.Range
  end
end
