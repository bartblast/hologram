defmodule Hologram.Compiler.CallGraph.FunctionDefinitionTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.IR.{FunctionDefinition, ModuleType}
  alias Hologram.Test.Fixtures.{PlaceholderModule1, PlaceholderModule2, PlaceholderModule3}

  test "build/4" do
    ir = %FunctionDefinition{
      module: PlaceholderModule1,
      name: :test_fun,
      body: [
        %ModuleType{module: PlaceholderModule2},
        %ModuleType{module: PlaceholderModule3}
      ]
    }

    call_graph = Graph.new()
    from_vertex = PlaceholderModule1

    result = CallGraph.build(ir, call_graph, %{}, from_vertex)

    assert Graph.num_vertices(result) == 4
    assert Graph.num_edges(result) == 3
    assert has_edge?(result, PlaceholderModule1, {PlaceholderModule1, :test_fun})
    assert has_edge?(result, {PlaceholderModule1, :test_fun}, PlaceholderModule2)
    assert has_edge?(result, {PlaceholderModule1, :test_fun}, PlaceholderModule3)
  end
end
