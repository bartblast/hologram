defmodule Hologram.Compiler.FunctionDefinitionTraverserTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.{FunctionCall, FunctionDefinition, ModuleDefinition}
  alias Hologram.Compiler.Traverser
  alias Hologram.Compiler.Traverser.Commons
  alias Hologram.Test.Fixtures.PlaceholderModule1
  alias Hologram.Test.Fixtures.PlaceholderModule2

  @initial_acc {%{}, Graph.new()}

  test "traverse/3" do
    ir = %FunctionDefinition{
      module: PlaceholderModule1,
      name: :test_fun_1a,
      body: [
        %FunctionCall{
          module: PlaceholderModule2, function: :test_fun_2a, params: []
        },
        %FunctionCall{
          module: PlaceholderModule2, function: :test_fun_2b, params: []
        }
      ]
    }

    {map, graph} = Traverser.traverse(ir, @initial_acc)

    assert Map.keys(map) == [PlaceholderModule2]
    assert %ModuleDefinition{} = map[PlaceholderModule2]

    vertex_1 = {PlaceholderModule1, :test_fun_1a}
    vertex_2 = {PlaceholderModule2, :test_fun_2a}
    vertex_3 = {PlaceholderModule2, :test_fun_2b}

    assert Graph.num_vertices(graph) == 3
    assert Graph.has_vertex?(graph, vertex_1)
    assert Graph.has_vertex?(graph, vertex_2)
    assert Graph.has_vertex?(graph, vertex_3)

    assert Graph.num_edges(graph) == 2
    assert Commons.has_edge?(graph, vertex_1, vertex_2)
    assert Commons.has_edge?(graph, vertex_1, vertex_3)
  end
end
