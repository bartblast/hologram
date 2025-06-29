defmodule Hologram.Compiler.Digraph2Test do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Digraph2
  alias Hologram.Compiler.Digraph2

  setup do
    [empty_graph: new()]
  end

  describe "add_vertex/2" do
    test "adds a single vertex when it doesn't exist yet", %{empty_graph: graph} do
      assert add_vertex(graph, :a) == %Digraph2{
               vertices: %{a: true},
               edges: %{},
               reverse_edges: %{}
             }
    end

    test "adds a single vertex when it already exists", %{empty_graph: graph} do
      graph_with_vetex_a = add_vertex(graph, :a)

      assert add_vertex(graph_with_vetex_a, :a) == %Digraph2{
               vertices: %{a: true},
               edges: %{},
               reverse_edges: %{}
             }
    end
  end

  describe "add_vertices/2" do
    test "adds multiple vertices", %{empty_graph: graph} do
      assert add_vertices(graph, [:a, :b]) == %Digraph2{
               vertices: %{a: true, b: true},
               edges: %{},
               reverse_edges: %{}
             }
    end
  end

  describe "new/0" do
    test "creates a new digraph" do
      assert new() == %Digraph2{vertices: %{}, edges: %{}, reverse_edges: %{}}
    end
  end
end
