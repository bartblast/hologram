defmodule Hologram.Compiler.ClauseBlameTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.ClauseBlame

  # Guards read out of BEAM debug info spell their calls out as :erlang remote
  # calls, so the fixtures below are shaped that way rather than as source AST.
  defp erlang_call(function, args) do
    {{:., [], [:erlang, function]}, [], args}
  end

  defp var(name) do
    {name, [], nil}
  end

  describe "build_guards/1" do
    test "clause without guards" do
      assert build_guards([]) == []
    end

    test "guard without and/or operators" do
      guard = erlang_call(:is_atom, [var(:module)])

      assert build_guards([guard]) == [{:leaf, "is_atom(module)", guard}]
    end

    test "guard with an and operator" do
      left = erlang_call(:is_integer, [var(:n)])
      right = erlang_call(:>=, [var(:n), 0])
      guard = erlang_call(:andalso, [left, right])

      assert build_guards([guard]) == [
               {:and, {:leaf, "is_integer(n)", left}, {:leaf, "n >= 0", right}}
             ]
    end

    test "guard with an or operator" do
      left = erlang_call(:==, [var(:timeout), :infinity])
      right = erlang_call(:is_integer, [var(:timeout)])
      guard = erlang_call(:orelse, [left, right])

      assert build_guards([guard]) == [
               {:or, {:leaf, "timeout == :infinity", left}, {:leaf, "is_integer(timeout)", right}}
             ]
    end

    test "guard with nested and/or operators" do
      leaf_1 = erlang_call(:==, [var(:timeout), :infinity])
      leaf_2 = erlang_call(:is_integer, [var(:timeout)])
      leaf_3 = erlang_call(:>=, [var(:timeout), 0])
      guard = erlang_call(:orelse, [leaf_1, erlang_call(:andalso, [leaf_2, leaf_3])])

      assert build_guards([guard]) == [
               {:or, {:leaf, "timeout == :infinity", leaf_1},
                {:and, {:leaf, "is_integer(timeout)", leaf_2}, {:leaf, "timeout >= 0", leaf_3}}}
             ]
    end

    test "multiple guards" do
      guard_1 = erlang_call(:is_atom, [var(:module)])
      guard_2 = erlang_call(:is_binary, [var(:module)])

      assert build_guards([guard_1, guard_2]) == [
               {:leaf, "is_atom(module)", guard_1},
               {:leaf, "is_binary(module)", guard_2}
             ]
    end

    test "guard calling a function outside Kernel" do
      guard = {{:., [], [:maps, :is_key]}, [], [:a, var(:map)]}

      assert build_guards([guard]) == [{:leaf, ":maps.is_key(:a, map)", guard}]
    end
  end

  describe "build_params/1" do
    test "clause without params" do
      assert build_params([]) == []
    end

    test "variable params" do
      assert build_params([var(:elem), var(:n)]) == ["elem", "n"]
    end

    test "literal param" do
      assert build_params([:abc]) == [":abc"]
    end

    test "struct param" do
      struct_pattern =
        {:%, [],
         [
           {:__aliases__, [alias: false], [:Task]},
           {:%{}, [], [ref: var(:ref), owner: var(:owner)]}
         ]}

      param = {:=, [], [struct_pattern, var(:task)]}

      assert build_params([param]) == ["%Task{ref: ref, owner: owner} = task"]
    end

    test "range param" do
      param = {:%{}, [], [__struct__: Range, first: 1, last: 3, step: 1]}

      assert build_params([param]) == ["1..3//1"]
    end
  end
end
