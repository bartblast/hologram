defmodule Hologram.Compiler.FunctionCallTraverserTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.{FunctionCall, ModuleDefinition}
  alias Hologram.Compiler.Traverser
  alias Hologram.Compiler.Traverser.Commons
  alias Hologram.Test.Fixtures.PlaceholderModule1
  alias Hologram.Test.Fixtures.PlaceholderModule2

  @acc {%{}, Graph.new()}
  @from_vertex {PlaceholderModule1, :test_fun_1a}
  @to_vertex {PlaceholderModule2, :test_fun_2a}

  @ir %FunctionCall{
    module: PlaceholderModule2,
    function: :test_fun_2a
  }

  defp test_result({map, graph}) do
    assert Map.keys(map) == [PlaceholderModule2]
    assert %ModuleDefinition{} = map[PlaceholderModule2]

    assert Graph.num_vertices(graph) == 2
    assert Graph.has_vertex?(graph, @from_vertex)
    assert Graph.has_vertex?(graph, @to_vertex)

    assert Graph.num_edges(graph) == 1
    assert Commons.has_edge?(graph, @from_vertex, @to_vertex)
  end

  test "called function that doesn't have a vertex in the call graph yet" do
    Traverser.traverse(@ir, @acc, @from_vertex)
    |> test_result()
  end

  test "called function that already has a vertex in the call graph" do
    {map, graph} = @acc
    graph = Graph.add_vertex(graph, @to_vertex)

    Traverser.traverse(@ir, {map, graph}, @from_vertex)
    |> test_result()
  end
end
