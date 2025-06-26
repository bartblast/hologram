defmodule Hologram.Compiler.DigraphTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Digraph
  alias Hologram.Compiler.Digraph

  describe "add_vertex/2" do
    test "adds a single vertex" do
      graph = new()
      result = add_vertex(graph, :a)

      assert result == graph

      vertices_table = graph.vertices_table

      assert :ets.member(vertices_table, :a)
      refute :ets.member(vertices_table, :b)

      # Also verify the stored format
      assert [{:a}] = :ets.lookup(vertices_table, :a)
      assert [] = :ets.lookup(vertices_table, :b)
    end
  end

  describe "new/0" do
    test "creates a new digraph" do
      graph = new()

      assert %Digraph{} = graph
      assert is_reference(graph.vertices_table)
      assert is_reference(graph.edges_table)
      assert is_reference(graph.reverse_edges_table)
    end
  end
end
