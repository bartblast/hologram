defmodule Hologram.Compiler.Traverser.CommonsTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.ModuleDefinition
  alias Hologram.Compiler.Traverser.Commons
  alias Hologram.Test.Fixtures.PlaceholderModule1

  describe "has_edge?/3" do
    test "returns true if the graph has an edge from from_vertex to to_vertex" do
      graph = Graph.new() |> Graph.add_edge(:a, :b)
      assert Commons.has_edge?(graph, :a, :b)
    end

    test "returns false if the graph doesn't have an edge from from_vertex to to_vertex" do
      refute Commons.has_edge?(Graph.new(), :a, :b)
    end
  end

  describe "maybe_add_module_def/2" do
    test "non standard lib module that isn't in the map yet is added" do
      result = Commons.maybe_add_module_def(%{}, PlaceholderModule1)

      assert Map.keys(result) == [PlaceholderModule1]
      assert %ModuleDefinition{} = result[PlaceholderModule1]
    end

    test "module that is in the map already is ignored" do
      result =
        Commons.maybe_add_module_def(%{}, PlaceholderModule1)
        |> Commons.maybe_add_module_def(PlaceholderModule1)

      assert Map.keys(result) == [PlaceholderModule1]
      assert %ModuleDefinition{} = result[PlaceholderModule1]
    end

    test "standard lib module is ignored" do
      result = Commons.maybe_add_module_def(%{}, Kernel)
      assert result == %{}
    end
  end
end
