defmodule Hologram.Compiler.ClauseBlameTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.ClauseBlame

  # Guards read out of BEAM debug info spell their calls out as :erlang remote
  # calls, so the fixtures below are shaped that way rather than as source AST.
  defp alias_ast(name) do
    {:__aliases__, [alias: false], [name]}
  end

  defp erlang_call(function, args) do
    {{:., [], [:erlang, function]}, [], args}
  end

  # Mirrors how the Elixir compiler spells an is_struct/1,2 guard out.
  defp struct_macro_guard(term) do
    map_check = erlang_call(:is_map, [term])
    key_check = erlang_call(:is_map_key, [:__struct__, term])
    struct_check = erlang_call(:is_atom, [erlang_call(:map_get, [:__struct__, term])])

    erlang_call(:andalso, [erlang_call(:andalso, [map_check, key_check]), struct_check])
  end

  defp struct_macro_guard(term, module) do
    map_check = erlang_call(:is_map, [term])
    module_check = erlang_call(:orelse, [erlang_call(:is_atom, [module]), :fail])
    key_check = erlang_call(:is_map_key, [:__struct__, term])

    struct_check =
      erlang_call(:==, [erlang_call(:map_get, [:__struct__, term]), module])

    erlang_call(:andalso, [
      erlang_call(:andalso, [erlang_call(:andalso, [map_check, module_check]), key_check]),
      struct_check
    ])
  end

  defp var(name) do
    {name, [], nil}
  end

  describe "build/2" do
    test "renders the clause head" do
      guard = erlang_call(:is_atom, [var(:module)])

      assert build([var(:module)], [guard]) ==
               %{params: ["module"], guards: [{:leaf, "is_atom(module)"}]}
    end

    test "returns nil when the clause head can't be rendered" do
      # Struct expansion can leave a variable whose context is an unresolved
      # alias, which Macro walking rejects.
      param = {:my_var, [], {:__aliases__, [alias: false], [:Kernel, :Utils]}}

      assert build([param], []) == nil
    end
  end

  describe "build_guards/1" do
    test "clause without guards" do
      assert build_guards([]) == []
    end

    test "guard without and/or operators" do
      guard = erlang_call(:is_atom, [var(:module)])

      assert build_guards([guard]) == [{:leaf, "is_atom(module)"}]
    end

    test "guard with an and operator" do
      left = erlang_call(:is_integer, [var(:n)])
      right = erlang_call(:>=, [var(:n), 0])
      guard = erlang_call(:andalso, [left, right])

      assert build_guards([guard]) == [{:and, {:leaf, "is_integer(n)"}, {:leaf, "n >= 0"}}]
    end

    test "guard with an or operator" do
      left = erlang_call(:==, [var(:timeout), :infinity])
      right = erlang_call(:is_integer, [var(:timeout)])
      guard = erlang_call(:orelse, [left, right])

      assert build_guards([guard]) == [
               {:or, {:leaf, "timeout == :infinity"}, {:leaf, "is_integer(timeout)"}}
             ]
    end

    test "guard with nested and/or operators" do
      leaf_1 = erlang_call(:==, [var(:timeout), :infinity])
      leaf_2 = erlang_call(:is_integer, [var(:timeout)])
      leaf_3 = erlang_call(:>=, [var(:timeout), 0])
      guard = erlang_call(:orelse, [leaf_1, erlang_call(:andalso, [leaf_2, leaf_3])])

      assert build_guards([guard]) == [
               {:or, {:leaf, "timeout == :infinity"},
                {:and, {:leaf, "is_integer(timeout)"}, {:leaf, "timeout >= 0"}}}
             ]
    end

    test "multiple guards" do
      guard_1 = erlang_call(:is_atom, [var(:module)])
      guard_2 = erlang_call(:is_binary, [var(:module)])

      assert build_guards([guard_1, guard_2]) == [
               {:leaf, "is_atom(module)"},
               {:leaf, "is_binary(module)"}
             ]
    end

    test "guard calling a function outside Kernel" do
      guard = {{:., [], [:maps, :is_key]}, [], [:a, var(:map)]}

      assert build_guards([guard]) == [{:leaf, ":maps.is_key(:a, map)"}]
    end

    test "guard spelling out an is_struct/1 call" do
      guard = struct_macro_guard(var(:term))

      assert build_guards([guard]) == [{:leaf, "is_struct(term)"}]
    end

    test "guard spelling out an is_struct/2 call" do
      guard = struct_macro_guard(var(:term), alias_ast(:MapSet))

      assert build_guards([guard]) == [{:leaf, "is_struct(term, MapSet)"}]
    end

    test "guard resembling but not spelling out an is_struct/1 call" do
      term = var(:term)
      map_check = erlang_call(:is_list, [term])
      key_check = erlang_call(:is_map_key, [:__struct__, term])
      struct_check = erlang_call(:is_atom, [erlang_call(:map_get, [:__struct__, term])])
      guard = erlang_call(:andalso, [erlang_call(:andalso, [map_check, key_check]), struct_check])

      assert build_guards([guard]) == [
               {:and, {:and, {:leaf, "is_list(term)"}, {:leaf, "is_map_key(term, :__struct__)"}},
                {:leaf, "is_atom(:erlang.map_get(:__struct__, term))"}}
             ]
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
