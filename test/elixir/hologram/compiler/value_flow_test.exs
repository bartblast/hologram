defmodule Hologram.Compiler.ValueFlowTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.ValueFlow

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.IR
  alias Hologram.Test.Fixtures.Compiler.ValueFlow.Module1
  alias Hologram.Test.Fixtures.Compiler.ValueFlow.Struct1

  # The fields an empty Struct1 literal holds: its field name and the default value.
  @struct_1_defaults MapSet.new([{:atom, :field}, {:atom, nil}])

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
      assert shapes_of(Module1, :match) == MapSet.new([{:struct, Struct1, @struct_1_defaults}])
    end

    test "module atom" do
      assert shapes_of(Module1, :module_atom) == MapSet.new([{:atom, Module1}])
    end

    test "nested" do
      list = {:list, MapSet.new([{:struct, Struct1, @struct_1_defaults}])}

      assert shapes_of(Module1, :nested) ==
               MapSet.new([{:tuple, [MapSet.new([{:atom, :ok}]), MapSet.new([list])]}])
    end

    test "string" do
      assert shapes_of(Module1, :string) == MapSet.new([:prim])
    end

    test "struct" do
      assert shapes_of(Module1, :struct) == MapSet.new([{:struct, Struct1, @struct_1_defaults}])
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
      assert shapes_of(Module1, :unknown) == top({Module1, :unknown, 1})
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
      mfa = {Module1, :unknown, 2}

      assert top(mfa) == MapSet.new([{:reach, mfa}, {:param, 0}, {:param, 1}])
    end

    test "function with no params" do
      mfa = {Module1, :atom, 0}

      assert top(mfa) == MapSet.new([{:reach, mfa}])
    end
  end
end
