defmodule Hologram.Compiler.ModuleTypeTraverserTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.{ModuleDefinition, ModuleType}
  alias Hologram.Compiler.Traverser
  alias Hologram.Compiler.Traverser.Commons
  alias Hologram.Test.Fixtures.PlaceholderModule1

  @initial_acc {%{}, Graph.new()}

  test "entry module" do
    ir = %ModuleType{module: PlaceholderModule1}
    {map, graph} = Traverser.traverse(ir, @initial_acc)

    assert Map.keys(map) == [PlaceholderModule1]
    assert %ModuleDefinition{} = map[PlaceholderModule1]

    assert graph.vertices == %{}
    assert graph.edges == %{}
  end

  test "non-entry module" do
    ir = %ModuleType{module: PlaceholderModule1}
    from_vertex = {PlaceholderModule1, :test_fun_1a}
    {map, graph} = Traverser.traverse(ir, @initial_acc, from_vertex)

    assert Map.keys(map) == [PlaceholderModule1]
    assert %ModuleDefinition{} = map[PlaceholderModule1]

    assert Graph.num_vertices(graph) == 2
    assert Graph.has_vertex?(graph, from_vertex)
    assert Graph.has_vertex?(graph, PlaceholderModule1)

    assert Graph.num_edges(graph) == 1
    assert Commons.has_edge?(graph, from_vertex, PlaceholderModule1)
  end
end
