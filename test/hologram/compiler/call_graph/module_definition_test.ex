defmodule Hologram.Compiler.CallGraph.ModuleDefinitionTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{CallGraph, Reflection}
  alias Hologram.Compiler.IR.{FunctionDefinition, ModuleDefinition, ModuleType}
  alias Hologram.E2E.DefaultLayout
  alias Hologram.Test.Fixtures.{PlaceholderModule1, PlaceholderModule2}
  alias Hologram.Test.Fixtures.Compiler.CallGraph.ModuleDefinition.{Module1, Module2, Module3}

  test "module that isn't in the call graph yet" do
    ir = %ModuleDefinition{
      module: PlaceholderModule1,
      functions: []
    }

    call_graph = Graph.new()

    result = CallGraph.build(ir, call_graph, %{})

    assert Graph.num_vertices(result) == 1
    assert Graph.num_edges(result) == 0
    assert Graph.has_vertex?(result, PlaceholderModule1)
  end

  test "module that is already in the call graph" do
    ir = %ModuleDefinition{
      module: PlaceholderModule1,
      functions: []
    }

    call_graph =
      Graph.new()
      |> Graph.add_vertex(PlaceholderModule1)

    result = CallGraph.build(ir, call_graph, %{})

    assert Graph.num_vertices(result) == 1
    assert Graph.num_edges(result) == 0
    assert Graph.has_vertex?(result, PlaceholderModule1)
  end

  test "functions traversing" do
    module_def_1 = %ModuleDefinition{
      module: PlaceholderModule1,
      functions: [
        %FunctionDefinition{
          module: PlaceholderModule1,
          name: :test_fun,
          body: [
            %ModuleType{module: PlaceholderModule2}
          ]
        }
      ]
    }

    module_def_2 = %ModuleDefinition{
     module: PlaceholderModule2
    }

    module_defs = %{
      PlaceholderModule1 => module_def_1,
      PlaceholderModule2 => module_def_2
    }

    call_graph = Graph.new()

    result = CallGraph.build(module_def_1, call_graph, module_defs)

    assert Graph.num_vertices(result) == 3
    assert Graph.has_vertex?(result, PlaceholderModule1)
    assert Graph.has_vertex?(result, PlaceholderModule2)
    assert Graph.has_vertex?(result, {PlaceholderModule1, :test_fun})

    assert Graph.num_edges(result) == 2
    has_edge?(call_graph, PlaceholderModule1, {PlaceholderModule1, :test_fun})
    has_edge?(call_graph, {PlaceholderModule1, :test_fun}, PlaceholderModule2)
  end
end
