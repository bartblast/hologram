defmodule Hologram.Compiler.CallGraph.ModuleDefinitionTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{CallGraph, Reflection}
  alias Hologram.Compiler.IR.{FunctionDefinition, ModuleDefinition}
  alias Hologram.E2E.DefaultLayout
  alias Hologram.Test.Fixtures.Compiler.CallGraph.ModuleDefinition.Module1
  alias Hologram.Test.Fixtures.Compiler.CallGraph.ModuleDefinition.Module2
  alias Hologram.Test.Fixtures.Compiler.CallGraph.ModuleDefinition.Module3
  alias Hologram.Test.Fixtures.PlaceholderModule1

  describe "build/4" do
    test "module without any functions" do
      ir = %ModuleDefinition{
        module: PlaceholderModule1,
        functions: []
      }

      call_graph = Graph.new()
      module_defs = %{PlaceholderModule1 => ir}
      result = CallGraph.build(ir, call_graph, module_defs)

      assert Graph.num_vertices(result) == 1
      assert Graph.num_edges(result) == 0
      assert Graph.has_vertex?(result, PlaceholderModule1)
    end

    test "module with functions" do
      ir = %ModuleDefinition{
        module: PlaceholderModule1,
        functions: [
          %FunctionDefinition{
            module: PlaceholderModule1,
            name: :test_fun
          }
        ]
      }

      call_graph = Graph.new()
      module_defs = %{PlaceholderModule1 => ir}
      result = CallGraph.build(ir, call_graph, module_defs)

      assert Graph.num_vertices(result) == 2
      assert Graph.num_edges(result) == 1
      assert has_edge?(result, PlaceholderModule1, {PlaceholderModule1, :test_fun})
    end
  end

  test "module that is not a page" do
    ir = %ModuleDefinition{
      module: PlaceholderModule1,
      functions: []
    }

    call_graph = Graph.new()
    module_defs = %{PlaceholderModule1 => ir}
    result = CallGraph.build(ir, call_graph, module_defs)

    assert Graph.num_vertices(result) == 1
    assert Graph.num_edges(result) == 0
    assert Graph.has_vertex?(result, PlaceholderModule1)
  end

  test "module that is a page with custom layout" do
    ir_1 = Reflection.module_definition(Module1)
    ir_2 = Reflection.module_definition(Module2)
    module_defs = %{Module1 => ir_1, Module2 => ir_2}

    call_graph = Graph.new()
    result = CallGraph.build(ir_1, call_graph, module_defs)

    assert has_edge?(result, Module1, Module2)
  end

  test "module that is a page with default layout" do
    ir_1 = Reflection.module_definition(Module3)
    ir_2 = Reflection.module_definition(DefaultLayout)
    module_defs = %{Module3 => ir_1, DefaultLayout => ir_2}

    call_graph = Graph.new()
    result = CallGraph.build(ir_1, call_graph, module_defs)

    assert has_edge?(result, Module3, DefaultLayout)
  end
end
