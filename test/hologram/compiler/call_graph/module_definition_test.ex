defmodule Hologram.Compiler.CallGraph.ModuleDefinitionTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.IR.{FunctionDefinition, ModuleDefinition}
  alias Hologram.Test.Fixtures.PlaceholderModule1

  describe "build/4" do
    test "module without any functions" do
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
      result = CallGraph.build(ir, call_graph, %{})

      assert Graph.num_vertices(result) == 2
      assert Graph.num_edges(result) == 1
      assert has_edge?(result, PlaceholderModule1, {PlaceholderModule1, :test_fun})
    end
  end
end
