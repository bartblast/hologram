defmodule Hologram.Compiler.ValueFlowTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.ValueFlow

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR
  alias Hologram.Test.Fixtures.Compiler.ValueFlow.Module1
  alias Hologram.Test.Fixtures.Compiler.ValueFlow.Module2
  alias Hologram.Test.Fixtures.Compiler.ValueFlow.Struct1
  alias Hologram.Test.Fixtures.Compiler.ValueFlow.Struct2

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

    test "variable of IR built from a code string is the function's top" do
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
end
