defmodule Hologram.Compiler.ClauseBlameTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.ClauseBlame

  alias Hologram.Compiler.IR

  # The functions whose ported raise sites report attempted clauses. Their
  # heads come from Elixir's own source, so they are compared against what the
  # server blames rather than against hardcoded text that would drift with the
  # Elixir version.
  @ported_calls [
    {Code, :ensure_compiled, [1]},
    {IO, :inspect, [123, :abc, []]},
    {String, :contains?, [:hello, "test"]},
    {String, :downcase, [:abc, :default]},
    {String, :replace, [:abc, "ab", "xy", []]},
    {String, :trim, [:abc]},
    {String, :upcase, [:abc, :default]},
    {Task, :await, [123, 5000]},
    {URI, :encode, [:hello, &URI.char_unreserved?/1]}
  ]

  # Guards read out of BEAM debug info spell their calls out as :erlang remote
  # calls, so the fixtures below are shaped that way rather than as source AST.
  defp alias_ast(name) do
    {:__aliases__, [alias: false], [name]}
  end

  # Reads the clause heads the compiler rendered for the given function.
  defp compiler_clause_heads(module, function, arity) do
    {_key, {_visibility, clauses}} =
      module
      |> IR.for_module()
      |> IR.aggregate_module_funs()
      |> List.keyfind({function, arity}, 0)

    Enum.map(clauses, & &1.blame)
  end

  defp erlang_call(function, args) do
    {{:., [], [:erlang, function]}, [], args}
  end

  # Renders the clause heads the server blames, dropping the marks, which
  # depend on the arguments and are placed by the client at raise time.
  defp server_clause_heads(module, function, args) do
    {:ok, _kind, clauses} = Exception.blame_mfa(module, function, args)

    Enum.map(clauses, fn {blamed_params, guards} ->
      %{
        params: Enum.map(blamed_params, &server_guard_source/1),
        guards: Enum.map(guards, &server_guard/1)
      }
    end)
  end

  defp server_guard({operator, _meta, [left, right]}) when operator in [:and, :or] do
    {operator, server_guard(left), server_guard(right)}
  end

  defp server_guard(node) do
    {:leaf, server_guard_source(node)}
  end

  defp server_guard_source(%{node: node}) do
    Macro.to_string(node)
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

  describe "rendering the clause heads of ported functions" do
    for {module, function, args} <- @ported_calls do
      arity = length(args)

      test "#{inspect(module)}.#{function}/#{arity}" do
        {module, function, args} = {unquote(module), unquote(function), unquote(args)}

        assert compiler_clause_heads(module, function, length(args)) ==
                 server_clause_heads(module, function, args)
      end
    end
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
      guard = erlang_call(:map_get, [:a, var(:map)])

      assert build_guards([guard]) == [{:leaf, ":erlang.map_get(:a, map)"}]
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
