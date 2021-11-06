defmodule Hologram.Compiler.CallGraph.FunctionCallTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{CallGraph, Reflection}
  alias Hologram.Compiler.IR.FunctionCall
  alias Hologram.Test.Fixtures.{PlaceholderModule1, PlaceholderModule2}

  @call_graph Graph.new()

  @module_defs %{
    PlaceholderModule1 => Reflection.module_definition(PlaceholderModule1),
    PlaceholderModule2 => Reflection.module_definition(PlaceholderModule2)
  }

  test "non-standard lib module" do
    ir = %FunctionCall{module: PlaceholderModule2, function: :test_fun_2a}
    from_vertex = PlaceholderModule1

    result = CallGraph.build(ir, @call_graph, @module_defs, from_vertex)

    assert has_edge?(result, PlaceholderModule1, {PlaceholderModule2, :test_fun_2a})
  end

  test "standard lib module" do
    ir = %FunctionCall{module: Kernel, function: :get_in}
    from_vertex = PlaceholderModule1

    result = CallGraph.build(ir, @call_graph, @module_defs, from_vertex)

    assert Graph.num_vertices(result) == 0
  end
end
