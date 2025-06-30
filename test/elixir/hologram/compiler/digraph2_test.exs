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

  describe "add_edges/2" do
    test "adds multiple edges", %{empty_graph: graph} do
      assert add_edges(graph, [{:a, :b}, {:b, :c}, {:d, :e}, {:d, :f}, {:g, :e}]) == %Digraph2{
               vertices: %{a: true, b: true, c: true, d: true, e: true, f: true, g: true},
               edges: %{a: %{b: true}, b: %{c: true}, d: %{e: true, f: true}, g: %{e: true}},
               reverse_edges: %{
                 b: %{a: true},
                 c: %{b: true},
                 e: %{d: true, g: true},
                 f: %{d: true}
               }
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
      graph_with_vertex_a = add_vertex(graph, :a)

      assert add_vertex(graph_with_vertex_a, :a) == %Digraph2{
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

  describe "remove_vertex/2" do
    test "removes a vertex that doesn't exist", %{empty_graph: graph} do
      result = remove_vertex(graph, :a)

      assert result == %Digraph2{
               vertices: %{},
               edges: %{},
               reverse_edges: %{}
             }
    end

    test "removes a vertex with no edges", %{empty_graph: graph} do
      result =
        graph
        |> add_vertex(:a)
        |> remove_vertex(:a)

      assert result == %Digraph2{
               vertices: %{},
               edges: %{},
               reverse_edges: %{}
             }
    end

    test "removes a vertex that has outgoing edges only", %{empty_graph: graph} do
      result =
        graph
        |> add_edge(:a, :b)
        |> add_edge(:a, :c)
        |> remove_vertex(:a)

      assert result == %Digraph2{
               vertices: %{b: true, c: true},
               edges: %{},
               reverse_edges: %{}
             }
    end

    test "removes a vertex that has incoming edges only", %{empty_graph: graph} do
      result =
        graph
        |> add_edge(:a, :c)
        |> add_edge(:b, :c)
        |> remove_vertex(:c)

      assert result == %Digraph2{
               vertices: %{a: true, b: true},
               edges: %{},
               reverse_edges: %{}
             }
    end

    test "removes a vertex that has both incoming and outgoing edges", %{empty_graph: graph} do
      result =
        graph
        |> add_edge(:a, :b)
        |> add_edge(:b, :c)
        |> remove_vertex(:b)

      assert result == %Digraph2{
               vertices: %{a: true, c: true},
               edges: %{},
               reverse_edges: %{}
             }
    end

    test "removes a vertex from a complex graph", %{empty_graph: graph} do
      result =
        graph
        |> add_edge(:a, :b)
        |> add_edge(:a, :h)
        |> add_edge(:b, :c)
        |> add_edge(:b, :i)
        |> add_edge(:c, :d)
        |> add_edge(:e, :b)
        |> add_edge(:f, :g)
        |> remove_vertex(:b)

      assert result == %Digraph2{
               vertices: %{a: true, c: true, d: true, e: true, f: true, g: true, h: true, i: true},
               edges: %{a: %{h: true}, c: %{d: true}, f: %{g: true}},
               reverse_edges: %{d: %{c: true}, g: %{f: true}, h: %{a: true}}
             }
    end
  end
end
