defmodule Hologram.Compiler.FunctionDefinitionTraverserTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.{FunctionCall, FunctionDefinition, ModuleDefinition}
  alias Hologram.Compiler.Traverser
  alias Hologram.Compiler.Traverser.Commons
  alias Hologram.Test.Fixtures.FunctionDefinitionTraverser.Module1
  alias Hologram.Test.Fixtures.PlaceholderModule

  @initial_acc {%{}, Graph.new()}

  test "traverse/3" do
    ir = %FunctionDefinition{
      module: PlaceholderModule,
      name: :test_fun_1,
      body: [
        %FunctionCall{
          module: Module1, function: :test_fun_2, params: []
        },
        %FunctionCall{
          module: Module1, function: :test_fun_3, params: []
        }
      ]
    }

    {map, graph} = Traverser.traverse(ir, @initial_acc)

    assert Map.keys(map) == [Module1]
    assert %ModuleDefinition{} = map[Module1]

    vertex_1 = {PlaceholderModule, :test_fun_1}
    vertex_2 = {Module1, :test_fun_2}
    vertex_3 = {Module1, :test_fun_3}

    assert Graph.num_vertices(graph) == 3
    assert Graph.has_vertex?(graph, vertex_1)
    assert Graph.has_vertex?(graph, vertex_2)
    assert Graph.has_vertex?(graph, vertex_3)

    assert Graph.num_edges(graph) == 2
    assert Commons.has_edge?(graph, vertex_1, vertex_2)
    assert Commons.has_edge?(graph, vertex_1, vertex_3)
  end
end
