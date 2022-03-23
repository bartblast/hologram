defmodule Hologram.Compiler.CallGraphBuilder.FunctionDefinitionTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.{CallGraph, CallGraphBuilder}
  alias Hologram.Compiler.IR.{FunctionDefinition, ModuleType}
  alias Hologram.Test.Fixtures.{PlaceholderModule1, PlaceholderModule2, PlaceholderModule3}

  @module_defs %{}
  @templates %{}

  setup do
    CallGraph.restart()
    :ok
  end

  test "function definition with call graph edges" do
    ir = %FunctionDefinition{
      module: PlaceholderModule1,
      name: :test_fun,
      body: [
        %ModuleType{module: PlaceholderModule2},
        %ModuleType{module: PlaceholderModule3}
      ]
    }

    from_vertex = PlaceholderModule1
    CallGraphBuilder.build(ir, @module_defs, @templates, from_vertex)

    assert CallGraph.num_vertices() == 3
    assert CallGraph.num_edges() == 2

    assert CallGraph.has_edge?({PlaceholderModule1, :test_fun}, PlaceholderModule2)
    assert CallGraph.has_edge?({PlaceholderModule1, :test_fun}, PlaceholderModule3)
  end

  test "function definition without call graph edges" do
    ir = %FunctionDefinition{
      module: PlaceholderModule1,
      name: :test_fun,
      body: []
    }

    from_vertex = PlaceholderModule1
    CallGraphBuilder.build(ir, @module_defs, @templates, from_vertex)

    assert CallGraph.num_vertices() == 1
    assert CallGraph.num_edges() == 0

    assert CallGraph.has_vertex?({PlaceholderModule1, :test_fun})
  end
end
