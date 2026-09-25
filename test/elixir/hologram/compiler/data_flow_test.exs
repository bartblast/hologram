defmodule Hologram.Compiler.DataFlowTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.DataFlow

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module1
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module2
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module3
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module4
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module5
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct1
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct2

  # The fields an empty Struct1 or Struct2 literal holds: its field name and the default value.
  @defaults MapSet.new([{:atom, :field}, {:atom, nil}])

  @param_0 MapSet.new([{:param, 0}])

  @struct_1 {:struct, Struct1, @defaults}
  @struct_2 {:struct, Struct2, @defaults}

  # What a pattern naming Struct1 with no fields names.
  @struct_1_named {:struct, Struct1, MapSet.new()}

  defp clause(module, function) do
    %IR.ModuleDefinition{body: %IR.Block{expressions: expressions}} = IR.for_module(module)

    Enum.find_value(expressions, fn
      %IR.FunctionDefinition{name: ^function, clause: clause} -> clause
      _expression -> nil
    end)
  end

  defp flow, do: start(PLT.start(), PLT.start())

  # The shapes of the value the given function of the given module returns, from its only clause.
  defp shapes_of(module, function) do
    %IR.FunctionClause{params: params, body: body} = clause = clause(module, function)

    shapes(body, clause, {module, function, length(params)}, flow())
  end

  defp summary_of(module, function, arity), do: summary({module, function, arity}, flow())

  defp types_fixture(modules, reach, structs) do
    %{modules: MapSet.new(modules), reach: MapSet.new(reach), structs: MapSet.new(structs)}
  end

  # The types of the given shapes, where Struct1 and Struct2 are struct modules and Module1 is a
  # module that defines no struct.
  defp types_of(shapes) do
    module_info_plt =
      PLT.put(PLT.start(), [
        {Module1, %{struct?: false}},
        {Struct1, %{struct?: true}},
        {Struct2, %{struct?: true}}
      ])

    shapes
    |> MapSet.new()
    |> types(start(PLT.start(), module_info_plt))
  end

  describe "apply_summary/2" do
    test "puts the arguments in for the params, at any depth" do
      summary = MapSet.new([{:list, @param_0}, {:tuple, [MapSet.new([{:param, 1}])]}])
      args = [MapSet.new([@struct_1]), MapSet.new([:prim])]

      assert apply_summary(summary, args) ==
               MapSet.new([{:list, MapSet.new([@struct_1])}, {:tuple, [MapSet.new([:prim])]}])
    end

    test "a missing argument gives nothing" do
      assert apply_summary(MapSet.new([{:param, 2}, {:atom, :ok}]), [@param_0]) ==
               MapSet.new([{:atom, :ok}])
    end

    test "keeps what holds no params" do
      summary = MapSet.new([{:reach, {Module3, :build, 0}}, :prim])

      assert apply_summary(summary, []) == summary
    end

    test "makes the call of an anonymous function a param stood for" do
      ref = {{Module5, :closure_arg, 0}, 1}
      fun = {:fun, ref, MapSet.new([{:tuple, [MapSet.new([{:arg, ref, 0}])]}])}
      summary = MapSet.new([{:call, @param_0, [MapSet.new([@struct_1])]}])

      assert apply_summary(summary, [MapSet.new([fun])]) ==
               MapSet.new([{:tuple, [MapSet.new([@struct_1])]}])
    end
  end

  describe "shapes/4" do
    test "atom" do
      assert shapes_of(Module1, :atom) == MapSet.new([{:atom, :ok}])
    end

    test "bitstring" do
      assert shapes_of(Module1, :bitstring) == MapSet.new([:prim])
    end

    test "block gives its last expression" do
      assert shapes_of(Module1, :block) == MapSet.new([{:atom, :ok}])
    end

    test "cons operator" do
      assert shapes_of(Module1, :cons) ==
               MapSet.new([{:list, MapSet.new([:prim, {:atom, :a}])}])
    end

    test "integer" do
      assert shapes_of(Module1, :integer) == MapSet.new([:prim])
    end

    test "list" do
      assert shapes_of(Module1, :list) ==
               MapSet.new([{:list, MapSet.new([:prim, {:atom, :a}])}])
    end

    test "map" do
      assert shapes_of(Module1, :map) ==
               MapSet.new([{:map, MapSet.new([{:atom, :a}, :prim])}])
    end

    test "match gives its right side" do
      assert shapes_of(Module1, :match) == MapSet.new([{:struct, Struct1, @defaults}])
    end

    test "module atom" do
      assert shapes_of(Module1, :module_atom) == MapSet.new([{:atom, Module1}])
    end

    test "nested" do
      list = {:list, MapSet.new([{:struct, Struct1, @defaults}])}

      assert shapes_of(Module1, :nested) ==
               MapSet.new([{:tuple, [MapSet.new([{:atom, :ok}]), MapSet.new([list])]}])
    end

    test "string" do
      assert shapes_of(Module1, :string) == MapSet.new([:prim])
    end

    test "struct" do
      assert shapes_of(Module1, :struct) == MapSet.new([{:struct, Struct1, @defaults}])
    end

    test "map with a __struct__ key is a struct" do
      assert shapes_of(Module1, :struct_map) ==
               MapSet.new([{:struct, Struct1, MapSet.new([{:atom, :field}, {:atom, :x}])}])
    end

    test "struct with fields" do
      assert shapes_of(Module1, :struct_with_fields) ==
               MapSet.new([{:struct, Struct1, MapSet.new([{:atom, :field}, {:atom, :x}])}])
    end

    test "tuple" do
      assert shapes_of(Module1, :tuple) ==
               MapSet.new([{:tuple, [MapSet.new([{:atom, :ok}]), MapSet.new([:prim])]}])
    end

    test "an expression it can't follow is the function's top" do
      expr = %IR.IgnoredExpression{type: :public_macro_definition}
      clause = %IR.FunctionClause{params: [], guards: [], body: %IR.Block{expressions: [expr]}}
      mfa = {Module1, :atom, 0}

      assert shapes(expr, clause, mfa, flow()) == top(mfa)
    end

    test "variable bound by a match" do
      assert shapes_of(Module2, :bound) == MapSet.new([@struct_1])
    end

    test "case gives every clause's value" do
      assert shapes_of(Module2, :case_clauses) == MapSet.new([@struct_1, @struct_2])
    end

    test "case condition variable takes what a clause's pattern names" do
      assert shapes_of(Module2, :case_named) ==
               MapSet.new([{:param, 0}, @struct_1_named, {:atom, nil}])
    end

    test "variables of the same name in two case clauses are apart" do
      assert shapes_of(Module2, :case_same_name) ==
               MapSet.new([{:tuple, [@param_0]}, {:list, @param_0}])
    end

    test "comprehension into a list" do
      assert shapes_of(Module2, :comprehension) == MapSet.new([{:list, MapSet.new([@struct_1])}])
    end

    test "comprehension into a map" do
      assert shapes_of(Module2, :comprehension_into_map) ==
               MapSet.new([{:map, MapSet.new([{:atom, :a}, @struct_1])}])
    end

    test "comprehension with a reducer" do
      mfa = {Module2, :comprehension_reduce, 0}
      body = {:tuple, [MapSet.new([:prim]), top(mfa)]}

      assert shapes_of(Module2, :comprehension_reduce) ==
               MapSet.new([{:bag, MapSet.new([@struct_1, body])}])
    end

    test "cond gives every clause's value" do
      assert shapes_of(Module2, :cond_clauses) == MapSet.new([@struct_1, @struct_2])
    end

    test "variable taken from a list" do
      assert shapes_of(Module2, :from_list) == MapSet.new([@struct_1])
    end

    test "variable taken from a map holds what the map holds" do
      assert shapes_of(Module2, :from_map) == MapSet.new([{:atom, :a}, @struct_1])
    end

    test "variable taken from a struct's field" do
      assert shapes_of(Module2, :from_struct_field) == MapSet.new([{:atom, :field}, @struct_2])
    end

    test "variable taken from a tuple" do
      assert shapes_of(Module2, :from_tuple) == MapSet.new([@struct_1])
    end

    test "variable taken from the tuples a pattern can match only" do
      assert shapes_of(Module2, :from_tuple_alternatives) == MapSet.new([@struct_1])
    end

    test "param" do
      assert shapes_of(Module2, :param) == @param_0
    end

    test "param matched against a struct pattern takes what the pattern names" do
      assert shapes_of(Module2, :param_named) == MapSet.new([{:param, 0}, @struct_1_named])
    end

    test "variable taken from a param keeps the param" do
      assert shapes_of(Module2, :param_pattern) == @param_0
    end

    test "rebound variable" do
      assert shapes_of(Module2, :rebound) ==
               MapSet.new([{:tuple, [MapSet.new([:prim]), MapSet.new([@struct_1])]}])
    end

    test "try with catch" do
      mfa = {Module2, :try_catch, 0}

      assert shapes_of(Module2, :try_catch) == MapSet.new([{:reach, mfa}, {:atom, :ok}])
    end

    test "try with else gives the else clauses' value instead of the body's" do
      assert shapes_of(Module2, :try_else) ==
               MapSet.new([{:tuple, [MapSet.new([@struct_1])]}, {:atom, :rescued}])
    end

    test "try with rescue of a module" do
      fields = top({Module2, :try_rescue, 0})

      assert shapes_of(Module2, :try_rescue) ==
               MapSet.new([{:atom, :ok}, {:struct, ArgumentError, fields}])
    end

    test "try with a bare rescue" do
      mfa = {Module2, :try_rescue_bare, 0}

      assert shapes_of(Module2, :try_rescue_bare) == MapSet.new([{:reach, mfa}, {:atom, :ok}])
    end

    test "variable no binding in the clause knows is the function's top" do
      var = IR.for_code("value", %Context{})
      clause = %IR.FunctionClause{params: [], guards: [], body: %IR.Block{expressions: [var]}}
      mfa = {Module2, :param, 1}

      assert shapes(var, clause, mfa, flow()) == top(mfa)
    end

    test "with and its else clauses" do
      assert shapes_of(Module2, :with_else) ==
               MapSet.new([{:tuple, [@param_0]}, {:list, @param_0}])
    end

    test "with clause expression variable takes what the clause's pattern names" do
      assert shapes_of(Module2, :with_named) == MapSet.new([{:param, 0}, @struct_1_named])
    end

    test "with without else gives an unmatched value too" do
      assert shapes_of(Module2, :with_no_else) == MapSet.new([{:tuple, [@param_0]}, {:param, 0}])
    end
  end

  test "start/2" do
    ir_plt = PLT.start()
    module_info_plt = PLT.start()

    assert %{ir_plt: ^ir_plt, module_info_plt: ^module_info_plt, summaries: %PLT{} = summaries} =
             start(ir_plt, module_info_plt)

    assert PLT.size(summaries) == 0
  end

  test "stop/1" do
    %{summaries: %PLT{pid: pid}} = flow = flow()

    assert stop(flow) == :ok
    refute Process.alive?(pid)
  end

  describe "summary/2" do
    test "anonymous function" do
      summary = summary_of(Module5, :closure, 0)

      assert [{:fun, {{Module5, :closure, 0}, _hash}, returned}] = MapSet.to_list(summary)

      assert returned == MapSet.new([@struct_1])
    end

    test "an anonymous function is the same on every pass" do
      assert summary_of(Module5, :closure, 0) == summary_of(Module5, :closure, 0)
    end

    test "call of an anonymous function" do
      assert summary_of(Module5, :calls_closure, 0) == MapSet.new([@struct_1])
    end

    test "call of an anonymous function with an argument" do
      assert summary_of(Module5, :closure_arg, 0) ==
               MapSet.new([{:tuple, [MapSet.new([{:atom, :ok}]), MapSet.new([@struct_1])]}])
    end

    test "anonymous function with two clauses" do
      assert summary_of(Module5, :closure_clauses, 0) == MapSet.new([@struct_1, @struct_2])
    end

    test "anonymous function reading a variable of its function" do
      assert summary_of(Module5, :closure_free_variable, 0) == MapSet.new([@struct_1])
    end

    test "anonymous function returning its function's param" do
      summary = summary_of(Module5, :closure_of_param, 1)

      assert [{:fun, _ref, returned}] = MapSet.to_list(summary)
      assert returned == @param_0
    end

    test "call of an anonymous function a call returned" do
      assert summary_of(Module5, :calls_closure_of_param, 0) == MapSet.new([@struct_1])
    end

    test "anonymous function's param shadowing its function's" do
      assert summary_of(Module5, :closure_shadowing_param, 1) ==
               MapSet.new([
                 {:tuple, [@param_0, MapSet.new([{:tuple, [MapSet.new([@struct_1])]}])]}
               ])
    end

    test "capture of a local function" do
      assert summary_of(Module5, :capture_local, 0) ==
               MapSet.new([{:tuple, [MapSet.new([{:atom, :ok}]), MapSet.new([@struct_1])]}])
    end

    test "capture of a remote function" do
      assert summary_of(Module5, :capture_remote, 0) == MapSet.new([@struct_1])
    end

    test "call of a param is made once the param is known" do
      assert summary_of(Module5, :higher_order, 1) ==
               MapSet.new([{:call, @param_0, [MapSet.new([@struct_1])]}])
    end

    test "anonymous function given to a function that calls it" do
      assert summary_of(Module5, :calls_higher_order, 0) ==
               MapSet.new([{:tuple, [MapSet.new([@struct_1]), MapSet.new([@struct_2])]}])
    end

    test "recursive function returning an anonymous function settles" do
      summary = summary_of(Module5, :recursive_closure, 1)

      assert [{:fun, _ref, returned}] = MapSet.to_list(summary)
      assert returned == MapSet.new([@struct_1])
    end

    test "function building a struct" do
      assert summary_of(Module3, :build, 0) == MapSet.new([@struct_1])
    end

    test "function building a struct from its param" do
      fields = MapSet.new([{:atom, :field}, {:param, 0}])

      assert summary_of(Module3, :build_from, 1) == MapSet.new([{:struct, Struct1, fields}])
    end

    test "call of a local function" do
      assert summary_of(Module3, :calls_build, 0) == MapSet.new([@struct_1])
    end

    test "call puts its arguments in the callee's summary" do
      fields = MapSet.new([{:atom, :field}, @struct_2])

      assert summary_of(Module3, :calls_build_from, 0) == MapSet.new([{:struct, Struct1, fields}])
    end

    test "call of an Erlang function gives everything it is given" do
      assert summary_of(Module3, :calls_erlang, 1) == MapSet.new([{:bag, @param_0}])
    end

    test "call of a remote function" do
      assert summary_of(Module3, :calls_remote, 0) == MapSet.new([@struct_1])
    end

    test "call whose value a pattern takes apart" do
      assert summary_of(Module3, :calls_wrap, 0) == MapSet.new([@struct_1])
    end

    test "an argument the callee's value doesn't hold is not followed" do
      flow = flow()

      assert summary({Module3, :calls_ignores, 0}, flow) == MapSet.new([{:atom, :ok}])
      refute PLT.member?(flow.summaries, {Module3, :build, 0})
    end

    test "a call whose value is dropped is not followed" do
      flow = flow()

      assert summary({Module3, :drops_result, 0}, flow) == MapSet.new([{:atom, :ok}])
      refute PLT.member?(flow.summaries, {Module3, :build, 0})
    end

    test "Erlang function" do
      assert summary_of(:lists, :reverse, 1) == MapSet.new([{:bag, @param_0}])
    end

    test "function its module doesn't define" do
      assert summary_of(Module3, :no_such_function, 0) == MapSet.new([{:bag, MapSet.new()}])
    end

    test "is kept in the analysis, with the summaries of the functions it calls" do
      flow = flow()
      summary = summary({Module3, :calls_build, 0}, flow)

      assert PLT.get(flow.summaries, {Module3, :calls_build, 0}) == {:ok, summary}
      assert PLT.get(flow.summaries, {Module3, :build, 0}) == {:ok, MapSet.new([@struct_1])}
    end

    test "param" do
      assert summary_of(Module3, :identity, 1) == @param_0
    end

    test "recursive function" do
      assert summary_of(Module3, :recursive, 1) == MapSet.new([@struct_1])
    end

    test "recursive function whose answer is found on a later pass" do
      assert summary_of(Module4, :direct, 1) == MapSet.new([@struct_1])
    end

    test "recursive function passing its param on" do
      assert summary_of(Module4, :join, 2) == MapSet.new([{:param, 1}, :prim])
    end

    test "a caller of a recursive function gets its final answer, and both are kept" do
      flow = flow()

      assert summary({Module4, :calls_direct, 0}, flow) == MapSet.new([@struct_1])
      assert PLT.get(flow.summaries, {Module4, :direct, 1}) == {:ok, MapSet.new([@struct_1])}
      assert PLT.member?(flow.summaries, {Module4, :calls_direct, 0})
    end

    test "mutually recursive functions" do
      assert summary_of(Module4, :mutual_a, 1) == MapSet.new([{:atom, :done}, @struct_2])
    end

    test "a summary that read an answer still in the making is not kept" do
      flow = flow()
      summary({Module4, :mutual_a, 1}, flow)

      assert PLT.member?(flow.summaries, {Module4, :mutual_a, 1})
      refute PLT.member?(flow.summaries, {Module4, :mutual_b, 1})
    end

    test "recursive function whose answer never settles takes its recursive calls' arguments" do
      count_minus_one = {:bag, MapSet.new([{:param, 0}, :prim])}
      recursive_call = {:bag, MapSet.new([count_minus_one])}

      assert summary_of(Module4, :growing, 1) ==
               MapSet.new([@struct_1, {:tuple, [MapSet.new([recursive_call])]}])
    end

    test "function with two clauses" do
      assert summary_of(Module3, :two_clauses, 1) == MapSet.new([@struct_1, @struct_2])
    end

    test "function returning its param in a tuple" do
      assert summary_of(Module3, :wrap, 1) ==
               MapSet.new([{:tuple, [MapSet.new([{:atom, :ok}]), @param_0]}])
    end
  end

  describe "top/1" do
    test "function with params" do
      mfa = {Module2, :param, 1}

      assert top(mfa) == MapSet.new([{:reach, mfa}, {:param, 0}])
    end

    test "function with no params" do
      mfa = {Module1, :atom, 0}

      assert top(mfa) == MapSet.new([{:reach, mfa}])
    end
  end

  describe "types/2" do
    test "struct" do
      assert types_of([@struct_1]) == types_fixture([], [], [Struct1])
    end

    test "struct in a struct's fields" do
      struct = {:struct, Struct1, MapSet.new([@struct_2])}

      assert types_of([struct]) == types_fixture([], [], [Struct1, Struct2])
    end

    test "module atom of a struct module" do
      assert types_of([{:atom, Struct1}]) == types_fixture([Struct1], [], [Struct1])
    end

    test "module atom of a module that defines no struct" do
      assert types_of([{:atom, Module1}]) == types_fixture([Module1], [], [])
    end

    test "atom that is no module the module info PLT knows" do
      assert types_of([{:atom, :ok}]) == types_fixture([], [], [])
    end

    test "reach" do
      mfa = {Module3, :build, 0}

      assert types_of([{:reach, mfa}]) == types_fixture([], [mfa], [])
    end

    test "param, anonymous function's argument and primitive hold nothing" do
      assert types_of([{:param, 0}, {:arg, make_ref(), 0}, :prim]) == types_fixture([], [], [])
    end

    test "tuple, list, map and bag hold what is inside them" do
      shapes = [
        {:tuple, [MapSet.new([@struct_1])]},
        {:list, MapSet.new([{:atom, Module1}])},
        {:map, MapSet.new([@struct_2])},
        {:bag, MapSet.new([{:reach, {Module3, :build, 0}}])}
      ]

      assert types_of(shapes) ==
               types_fixture([Module1], [{Module3, :build, 0}], [Struct1, Struct2])
    end

    test "anonymous function holds what it returns" do
      assert types_of([{:fun, make_ref(), MapSet.new([@struct_1])}]) ==
               types_fixture([], [], [Struct1])
    end

    test "call not made holds its function and its arguments" do
      shapes = [{:call, MapSet.new([@struct_1]), [MapSet.new([@struct_2])]}]

      assert types_of(shapes) == types_fixture([], [], [Struct1, Struct2])
    end

    test "dynamic call not made holds its module and its arguments" do
      shapes = [{:dyn, MapSet.new([{:atom, Module1}]), :build, 1, [MapSet.new([@struct_2])]}]

      assert types_of(shapes) == types_fixture([Module1], [], [Struct2])
    end
  end
end
