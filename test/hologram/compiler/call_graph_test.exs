defmodule Hologram.Compiler.CallGraphTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.IR.ModuleDefinition

  defp has_edge?(graph, from_vertex, to_vertex) do
    edges = Graph.edges(graph, from_vertex, to_vertex)
    Enum.count(edges) == 1
  end

  test "empty module" do
    module = Hologram.Test.Fixtures.CallGraph.Module1
    {map, graph} = CallGraph.build(module)

    assert Map.keys(map) == [module]
    assert %ModuleDefinition{} = map[module]

    assert graph.vertices == %{}
    assert graph.edges == %{}
  end

  test "function definition without any function calls" do
    module = Hologram.Test.Fixtures.CallGraph.Module2
    {map, graph} = CallGraph.build(module)

    assert Map.keys(map) == [module]
    assert %ModuleDefinition{} = map[module]

    assert graph.vertices == %{}
    assert graph.edges == %{}
  end

  test "function definition with a local function call" do
    module = Hologram.Test.Fixtures.CallGraph.Module3
    {map, graph} = CallGraph.build(module)

    assert Map.keys(map) == [module]
    assert %ModuleDefinition{} = map[module]

    assert Graph.num_vertices(graph) == 2
    assert Graph.has_vertex?(graph, {module, :test_fun_1})
    assert Graph.has_vertex?(graph, {module, :test_fun_2})

    assert Graph.num_edges(graph) == 1
    assert has_edge?(graph, {module, :test_fun_1}, {module, :test_fun_2})
  end
end
