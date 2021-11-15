defmodule Hologram.Compiler.CallGraph.FunctionCallTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{CallGraph, Reflection}
  alias Hologram.Compiler.IR.FunctionCall
  alias Hologram.Test.Fixtures.{PlaceholderModule1, PlaceholderModule2, PlaceholderModule3, PlaceholderModule4}

  @call_graph Graph.new()
  @from_vertex {PlaceholderModule4, :test_fun_4a}

  @module_defs %{
    PlaceholderModule1 => Reflection.module_definition(PlaceholderModule1),
    PlaceholderModule2 => Reflection.module_definition(PlaceholderModule2),
    PlaceholderModule3 => Reflection.module_definition(PlaceholderModule3),
    PlaceholderModule4 => Reflection.module_definition(PlaceholderModule4)
  }

  test "non-standard lib module" do
    ir = %FunctionCall{module: PlaceholderModule2, function: :test_fun_2a}
    result = CallGraph.build(ir, @call_graph, @module_defs, @from_vertex)

    assert has_edge?(result, @from_vertex, {PlaceholderModule2, :test_fun_2a})
  end

  test "standard lib module" do
    ir = %FunctionCall{module: Kernel, function: :get_in}
    result = CallGraph.build(ir, @call_graph, @module_defs, @from_vertex)

    assert Graph.num_vertices(result) == 0
  end

  test "args recursion" do
    args = [
      %FunctionCall{module: PlaceholderModule2, function: :test_fun_2a},
      %FunctionCall{module: PlaceholderModule3, function: :test_fun_3a}
    ]

    ir = %FunctionCall{module: PlaceholderModule1, function: :test_fun_1a, args: args}
    result = CallGraph.build(ir, @call_graph, @module_defs, @from_vertex)

    assert has_edge?(result, @from_vertex, {PlaceholderModule2, :test_fun_2a})
    assert has_edge?(result, @from_vertex, {PlaceholderModule3, :test_fun_3a})
  end
end
