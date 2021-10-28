defmodule Hologram.Compiler.ModuleTypeTraverserTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.{ModuleDefinition, ModuleType}
  alias Hologram.Compiler.Traverser
  alias Hologram.Compiler.Traverser.Commons

  @initial_acc {%{}, Graph.new()}

  describe "traverse/3" do
    test "entry module" do
      module = Hologram.Test.Fixtures.ModuleTypeTraverser.Module1
      ir = %ModuleType{module: module}
      {map, graph} = Traverser.traverse(ir, @initial_acc)

      assert Map.keys(map) == [module]
      assert %ModuleDefinition{} = map[module]

      assert graph.vertices == %{}
      assert graph.edges == %{}
    end

    test "non-entry module" do
      module = Hologram.Test.Fixtures.ModuleTypeTraverser.Module1
      ir = %ModuleType{module: module}
      from_vertex = {Hologram.Test.Fixtures.PlaceholderModule, :test_fun}
      {map, graph} = Traverser.traverse(ir, @initial_acc, from_vertex)

      assert Map.keys(map) == [module]
      assert %ModuleDefinition{} = map[module]

      assert Graph.num_vertices(graph) == 2
      assert Graph.has_vertex?(graph, from_vertex)
      assert Graph.has_vertex?(graph, module)

      assert Graph.num_edges(graph) == 1
      assert Commons.has_edge?(graph, from_vertex, module)
    end
  end
end
