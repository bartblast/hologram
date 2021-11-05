defmodule Hologram.Compiler.CallGraph.IfExpressionTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.IR.{ModuleType, IfExpression, NilType}
  alias Hologram.Test.Fixtures.{PlaceholderModule1, PlaceholderModule2}

  test "condition is traversed" do
    ir = %IfExpression{
      condition: %ModuleType{module: PlaceholderModule2},
      do: %NilType{},
      else: %NilType{}
    }

    call_graph = Graph.new()
    result = CallGraph.build(ir, call_graph, %{}, PlaceholderModule1)

    assert Graph.num_vertices(result) == 2
    assert Graph.num_edges(result) == 1
    has_edge?(call_graph, PlaceholderModule1, PlaceholderModule2)
  end

  test "do clause is traversed" do
    ir = %IfExpression{
      condition: %NilType{},
      do: %ModuleType{module: PlaceholderModule2},
      else: %NilType{}
    }

    call_graph = Graph.new()
    result = CallGraph.build(ir, call_graph, %{}, PlaceholderModule1)

    assert Graph.num_vertices(result) == 2
    assert Graph.num_edges(result) == 1
    has_edge?(call_graph, PlaceholderModule1, PlaceholderModule2)
  end

  test "else clause is traversed" do
    ir = %IfExpression{
      condition: %NilType{},
      do: %NilType{},
      else: %ModuleType{module: PlaceholderModule2}
    }

    call_graph = Graph.new()
    result = CallGraph.build(ir, call_graph, %{}, PlaceholderModule1)

    assert Graph.num_vertices(result) == 2
    assert Graph.num_edges(result) == 1
    has_edge?(call_graph, PlaceholderModule1, PlaceholderModule2)
  end
end
