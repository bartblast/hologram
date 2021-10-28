defmodule Hologram.Compiler.VDOMNodeListTraverserTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.{ModuleDefinition, ModuleType}
  alias Hologram.Compiler.Traverser
  alias Hologram.Compiler.Traverser.Commons
  alias Hologram.Test.Fixtures.{PlaceholderModule1, PlaceholderModule2, PlaceholderModule3}

  @acc {%{}, Graph.new()}

  test "traverse/3" do
    ir = [
      %ModuleType{module: PlaceholderModule2},
      %ModuleType{module: PlaceholderModule3}
    ]

    from_vertex = {PlaceholderModule1, :test_fun_1a}
    {map, graph} = Traverser.traverse(ir, @acc, from_vertex)

    assert Map.keys(map) == [PlaceholderModule2, PlaceholderModule3]
    assert %ModuleDefinition{} = map[PlaceholderModule2]
    assert %ModuleDefinition{} = map[PlaceholderModule3]

    assert Graph.num_vertices(graph) == 3
    assert Graph.has_vertex?(graph, from_vertex)
    assert Graph.has_vertex?(graph, PlaceholderModule2)
    assert Graph.has_vertex?(graph, PlaceholderModule3)

    assert Graph.num_edges(graph) == 2
    assert Commons.has_edge?(graph, from_vertex, PlaceholderModule2)
    assert Commons.has_edge?(graph, from_vertex, PlaceholderModule3)
  end
end
