defmodule Hologram.Compiler.Digraph2Test do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Digraph2
  alias Hologram.Compiler.Digraph2

  setup do
    [empty_graph: new()]
  end

  describe "add_edge/3" do
    test "adds an edge when there are no source or target vertices yet", %{empty_graph: graph} do
      result = add_edge(graph, :a, :b)

      assert result == %Digraph2{
               vertices: %{a: true, b: true},
               outgoing_edges: %{a: %{b: true}},
               incoming_edges: %{b: %{a: true}}
             }
    end

    test "adds edge from a vertex that is already a source of another edge", %{empty_graph: graph} do
      result =
        graph
        |> add_edge(:a, :b)
        |> add_edge(:a, :c)

      assert result == %Digraph2{
               vertices: %{a: true, b: true, c: true},
               outgoing_edges: %{a: %{b: true, c: true}},
               incoming_edges: %{b: %{a: true}, c: %{a: true}}
             }
    end

    test "adds edge to a vertex that is already a target of another edge", %{empty_graph: graph} do
      result =
        graph
        |> add_edge(:a, :b)
        |> add_edge(:c, :b)

      assert result == %Digraph2{
               vertices: %{a: true, b: true, c: true},
               outgoing_edges: %{a: %{b: true}, c: %{b: true}},
               incoming_edges: %{b: %{a: true, c: true}}
             }
    end
  end

  describe "add_edges/2" do
    test "adds multiple edges", %{empty_graph: graph} do
      result = add_edges(graph, [{:a, :b}, {:b, :c}, {:d, :e}, {:d, :f}, {:g, :e}])

      assert result == %Digraph2{
               vertices: %{a: true, b: true, c: true, d: true, e: true, f: true, g: true},
               outgoing_edges: %{
                 a: %{b: true},
                 b: %{c: true},
                 d: %{e: true, f: true},
                 g: %{e: true}
               },
               incoming_edges: %{
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
      result = add_vertex(graph, :a)

      assert result == %Digraph2{
               vertices: %{a: true},
               outgoing_edges: %{},
               incoming_edges: %{}
             }
    end

    test "adds a vertex when it already exists", %{empty_graph: graph} do
      result =
        graph
        |> add_vertex(:a)
        |> add_vertex(:a)

      assert result == %Digraph2{
               vertices: %{a: true},
               outgoing_edges: %{},
               incoming_edges: %{}
             }
    end
  end

  describe "add_vertices/2" do
    test "adds multiple vertices", %{empty_graph: graph} do
      result = add_vertices(graph, [:a, :b])

      assert result == %Digraph2{
               vertices: %{a: true, b: true},
               outgoing_edges: %{},
               incoming_edges: %{}
             }
    end
  end

  describe "new/0" do
    test "creates a new digraph" do
      result = new()

      assert result == %Digraph2{vertices: %{}, outgoing_edges: %{}, incoming_edges: %{}}
    end
  end

  describe "remove_vertex/2" do
    test "removes a vertex that doesn't exist", %{empty_graph: graph} do
      result = remove_vertex(graph, :a)

      assert result == %Digraph2{
               vertices: %{},
               outgoing_edges: %{},
               incoming_edges: %{}
             }
    end

    test "removes a vertex with no edges", %{empty_graph: graph} do
      result =
        graph
        |> add_vertex(:a)
        |> remove_vertex(:a)

      assert result == %Digraph2{
               vertices: %{},
               outgoing_edges: %{},
               incoming_edges: %{}
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
               outgoing_edges: %{},
               incoming_edges: %{}
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
               outgoing_edges: %{},
               incoming_edges: %{}
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
               outgoing_edges: %{},
               incoming_edges: %{}
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
               outgoing_edges: %{a: %{h: true}, c: %{d: true}, f: %{g: true}},
               incoming_edges: %{d: %{c: true}, g: %{f: true}, h: %{a: true}}
             }
    end
  end

  describe "remove_vertices/2" do
    test "handles empty list of vertices", %{empty_graph: graph} do
      result =
        graph
        |> add_edge(:a, :b)
        |> remove_vertices([])

      assert result == %Digraph2{
               vertices: %{a: true, b: true},
               outgoing_edges: %{a: %{b: true}},
               incoming_edges: %{b: %{a: true}}
             }
    end

    test "handles vertices that don't exist", %{empty_graph: graph} do
      result = remove_vertices(graph, [:a, :b])

      assert result == %Digraph2{
               vertices: %{},
               outgoing_edges: %{},
               incoming_edges: %{}
             }
    end

    test "removes vertices with no edges", %{empty_graph: graph} do
      result =
        graph
        |> add_vertices([:a, :b])
        |> remove_vertices([:a, :b])

      assert result == %Digraph2{
               vertices: %{},
               outgoing_edges: %{},
               incoming_edges: %{}
             }
    end

    test "removes vertices that have outgoing edges only", %{empty_graph: graph} do
      result =
        graph
        |> add_edge(:a1, :b1)
        |> add_edge(:a1, :c1)
        |> add_edge(:a2, :b2)
        |> add_edge(:a2, :c2)
        |> remove_vertices([:a1, :a2])

      assert result == %Digraph2{
               vertices: %{b1: true, b2: true, c1: true, c2: true},
               outgoing_edges: %{},
               incoming_edges: %{}
             }
    end

    test "removes vertices that have incoming edges only", %{empty_graph: graph} do
      result =
        graph
        |> add_edge(:a1, :c1)
        |> add_edge(:b1, :c1)
        |> add_edge(:a2, :c2)
        |> add_edge(:b2, :c2)
        |> remove_vertices([:c1, :c2])

      assert result == %Digraph2{
               vertices: %{a1: true, a2: true, b1: true, b2: true},
               outgoing_edges: %{},
               incoming_edges: %{}
             }
    end

    test "removes vertices that have both incoming and outgoing edges", %{empty_graph: graph} do
      result =
        graph
        |> add_edge(:a1, :b1)
        |> add_edge(:b1, :c1)
        |> add_edge(:a2, :b2)
        |> add_edge(:b2, :c2)
        |> remove_vertices([:b1, :b2])

      assert result == %Digraph2{
               vertices: %{a1: true, a2: true, c1: true, c2: true},
               outgoing_edges: %{},
               incoming_edges: %{}
             }
    end

    test "removes vertices from a complex graph", %{empty_graph: graph} do
      result =
        graph
        |> add_edge(:a1, :b1)
        |> add_edge(:a1, :h1)
        |> add_edge(:b1, :c1)
        |> add_edge(:b1, :i1)
        |> add_edge(:c1, :d1)
        |> add_edge(:e1, :b1)
        |> add_edge(:f1, :g1)
        |> add_edge(:a2, :b2)
        |> add_edge(:a2, :h2)
        |> add_edge(:b2, :c2)
        |> add_edge(:b2, :i2)
        |> add_edge(:c2, :d2)
        |> add_edge(:e2, :b2)
        |> add_edge(:f2, :g2)
        |> remove_vertices([:b1, :b2])

      assert result == %Digraph2{
               vertices: %{
                 a1: true,
                 c1: true,
                 d1: true,
                 e1: true,
                 f1: true,
                 g1: true,
                 h1: true,
                 i1: true,
                 a2: true,
                 c2: true,
                 d2: true,
                 e2: true,
                 f2: true,
                 g2: true,
                 h2: true,
                 i2: true
               },
               outgoing_edges: %{
                 a1: %{h1: true},
                 a2: %{h2: true},
                 c1: %{d1: true},
                 c2: %{d2: true},
                 f1: %{g1: true},
                 f2: %{g2: true}
               },
               incoming_edges: %{
                 d1: %{c1: true},
                 d2: %{c2: true},
                 g1: %{f1: true},
                 g2: %{f2: true},
                 h1: %{a1: true},
                 h2: %{a2: true}
               }
             }
    end
  end
end
