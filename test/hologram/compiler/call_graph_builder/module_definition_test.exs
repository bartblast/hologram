defmodule Hologram.Compiler.CallGraphBuilder.ModuleDefinitionTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{CallGraphBuilder, Reflection}
  alias Hologram.Compiler.IR.{FunctionDefinition, ModuleDefinition, ModuleType}
  alias Hologram.Test.Fixtures.{PlaceholderModule1, PlaceholderModule2}
  alias Hologram.Test.Fixtures.Compiler.CallGraphBuilder.ModuleDefinition.{Module4, Module5}

  test "module that isn't in the call graph yet" do
    module_def = Reflection.module_definition(PlaceholderModule1)
    module_defs = %{PlaceholderModule1 => module_def}
    call_graph = Graph.new()

    result = CallGraphBuilder.build(module_def, call_graph, module_defs)

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

    result = CallGraphBuilder.build(ir, call_graph, %{})

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

    result = CallGraphBuilder.build(module_def_1, call_graph, module_defs)

    assert Graph.num_vertices(result) == 3
    assert Graph.num_edges(result) == 1
    has_edge?(call_graph, {PlaceholderModule1, :test_fun}, PlaceholderModule2)
  end

  test "template traversing" do
    module_defs = %{
      Module4 => Reflection.module_definition(Module4),
      Module5 => Reflection.module_definition(Module5),
    }

    call_graph = Graph.new()

    result = CallGraphBuilder.build(module_defs[Module4], call_graph, module_defs)

    assert Graph.has_vertex?(result, Module5)
    assert has_edge?(result, {Module4, :template}, Module5)
  end
end
