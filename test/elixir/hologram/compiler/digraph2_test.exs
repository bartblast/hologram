defmodule Hologram.Compiler.Digraph2Test do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Digraph2
  alias Hologram.Compiler.Digraph2

  setup do
    [empty_graph: new()]
  end

  describe "add_edge/3" do
    test "adds an edge when there are no source or target vertices yet", %{empty_graph: graph} do
      assert add_edge(graph, :a, :b) == %Digraph2{
               vertices: %{a: true, b: true},
               edges: %{a: %{b: true}},
               reverse_edges: %{b: %{a: true}}
             }
    end

    test "adds edge from a vertex that is already a source of another edge", %{empty_graph: graph} do
      result =
        graph
        |> add_edge(:a, :b)
        |> add_edge(:a, :c)

      assert result == %Digraph2{
               vertices: %{a: true, b: true, c: true},
               edges: %{a: %{b: true, c: true}},
               reverse_edges: %{b: %{a: true}, c: %{a: true}}
             }
    end

    test "adds edge to a vertex that is already a target of another edge", %{empty_graph: graph} do
      result =
        graph
        |> add_edge(:a, :b)
        |> add_edge(:c, :b)

      assert result == %Digraph2{
               vertices: %{a: true, b: true, c: true},
               edges: %{a: %{b: true}, c: %{b: true}},
               reverse_edges: %{b: %{a: true, c: true}}
             }
    end
  end

  describe "add_vertex/2" do
    test "adds a vertex when it doesn't exist yet", %{empty_graph: graph} do
      assert add_vertex(graph, :a) == %Digraph2{
               vertices: %{a: true},
               edges: %{},
               reverse_edges: %{}
             }
    end

    test "adds a vertex when it already exists", %{empty_graph: graph} do
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
