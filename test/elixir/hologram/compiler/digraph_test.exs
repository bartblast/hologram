defmodule Hologram.Compiler.DigraphTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Digraph
  alias Hologram.Compiler.Digraph

  describe "add_edge/3" do
    test "adds an edge when there are no source or target vertices yet" do
      result = add_edge(new(), :a, :b)

      assert result == %Digraph{
               vertices: %{a: true, b: true},
               outgoing_edges: %{a: %{b: true}},
               incoming_edges: %{b: %{a: true}}
             }
    end

    test "adds edge from a vertex that is already a source of another edge" do
      result =
        new()
        |> add_edge(:a, :b)
        |> add_edge(:a, :c)

      assert result == %Digraph{
               vertices: %{a: true, b: true, c: true},
               outgoing_edges: %{a: %{b: true, c: true}},
               incoming_edges: %{b: %{a: true}, c: %{a: true}}
             }
    end

    test "adds edge to a vertex that is already a target of another edge" do
      result =
        new()
        |> add_edge(:a, :b)
        |> add_edge(:c, :b)

      assert result == %Digraph{
               vertices: %{a: true, b: true, c: true},
               outgoing_edges: %{a: %{b: true}, c: %{b: true}},
               incoming_edges: %{b: %{a: true, c: true}}
             }
    end
  end

  describe "add_edges/2" do
    test "adds multiple edges" do
      result = add_edges(new(), [{:a, :b}, {:b, :c}, {:d, :e}, {:d, :f}, {:g, :e}])

      assert result == %Digraph{
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
    test "adds a vertex when it doesn't exist yet" do
      result = add_vertex(new(), :a)

      assert result == %Digraph{
               vertices: %{a: true},
               outgoing_edges: %{},
               incoming_edges: %{}
             }
    end

    test "adds a vertex when it already exists" do
      result =
        new()
        |> add_vertex(:a)
        |> add_vertex(:a)

      assert result == %Digraph{
               vertices: %{a: true},
               outgoing_edges: %{},
               incoming_edges: %{}
             }
    end
  end

  describe "add_vertices/2" do
    test "adds multiple vertices" do
      result = add_vertices(new(), [:a, :b])

      assert result == %Digraph{
               vertices: %{a: true, b: true},
               outgoing_edges: %{},
               incoming_edges: %{}
             }
    end
  end

  describe "edges/1" do
    test "returns empty list when graph is empty" do
      result = edges(new())

      assert result == []
    end

    test "returns empty list when graph has only vertices but no edges" do
      result =
        new()
        |> add_vertices([:a, :b, :c])
        |> edges()

      assert result == []
    end

    test "returns single edge when graph has one edge" do
      result =
        new()
        |> add_edge(:a, :b)
        |> edges()

      assert result == [{:a, :b}]
    end

    test "returns multiple edges from single source vertex" do
      result =
        new()
        |> add_edge(:a, :b)
        |> add_edge(:a, :c)
        |> add_edge(:a, :d)
        |> edges()

      assert Enum.sort(result) == [{:a, :b}, {:a, :c}, {:a, :d}]
    end

    test "returns multiple edges to single target vertex" do
      result =
        new()
        |> add_edge(:a, :d)
        |> add_edge(:b, :d)
        |> add_edge(:c, :d)
        |> edges()

      assert Enum.sort(result) == [{:a, :d}, {:b, :d}, {:c, :d}]
    end

    test "returns all edges in linear chain" do
      result =
        new()
        |> add_edge(:a, :b)
        |> add_edge(:b, :c)
        |> add_edge(:c, :d)
        |> edges()

      assert Enum.sort(result) == [{:a, :b}, {:b, :c}, {:c, :d}]
    end

    test "includes self-loop edge" do
      result =
        new()
        |> add_edge(:a, :a)
        |> edges()

      assert result == [{:a, :a}]
    end

    test "returns all edges in graph with cycles" do
      result =
        new()
        |> add_edge(:a, :b)
        |> add_edge(:b, :c)
        |> add_edge(:c, :a)
        |> add_edge(:a, :d)
        |> edges()

      assert Enum.sort(result) == [{:a, :b}, {:a, :d}, {:b, :c}, {:c, :a}]
    end

    test "returns all edges in disconnected graph" do
      result =
        new()
        |> add_edge(:a, :b)
        |> add_edge(:b, :c)
        # disconnected component
        |> add_edge(:x, :y)
        |> add_edge(:y, :z)
        # isolated vertex
        |> add_vertex(:isolated)
        |> edges()

      assert Enum.sort(result) == [{:a, :b}, {:b, :c}, {:x, :y}, {:y, :z}]
    end
  end

  describe "has_edge?/3" do
    test "returns false when graph is empty" do
      result = has_edge?(new(), :a, :b)

      assert result == false
    end

    test "returns false when source vertex doesn't exist" do
      result =
        new()
        |> add_vertex(:b)
        |> has_edge?(:a, :b)

      assert result == false
    end

    test "returns false when target vertex doesn't exist" do
      result =
        new()
        |> add_vertex(:a)
        |> has_edge?(:a, :b)

      assert result == false
    end

    test "returns false when neither vertex exists" do
      result =
        new()
        |> add_vertex(:c)
        |> has_edge?(:a, :b)

      assert result == false
    end

    test "returns false when both vertices exist but no edge exists" do
      result =
        new()
        |> add_vertex(:a)
        |> add_vertex(:b)
        |> has_edge?(:a, :b)

      assert result == false
    end

    test "returns true when edge exists" do
      result =
        new()
        |> add_edge(:a, :b)
        |> has_edge?(:a, :b)

      assert result == true
    end

    test "returns false for reverse direction of existing edge" do
      result =
        new()
        |> add_edge(:a, :b)
        |> has_edge?(:b, :a)

      assert result == false
    end

    test "returns true for self-loop edge" do
      result =
        new()
        |> add_edge(:a, :a)
        |> has_edge?(:a, :a)

      assert result == true
    end

    test "returns true for one of multiple edges from same source" do
      graph =
        new()
        |> add_edge(:a, :b)
        |> add_edge(:a, :c)
        |> add_edge(:a, :d)

      assert has_edge?(graph, :a, :b) == true
      assert has_edge?(graph, :a, :c) == true
      assert has_edge?(graph, :a, :d) == true
      assert has_edge?(graph, :a, :e) == false
    end

    test "returns true for edges to same target from different sources" do
      graph =
        new()
        |> add_edge(:a, :d)
        |> add_edge(:b, :d)
        |> add_edge(:c, :d)

      assert has_edge?(graph, :a, :d) == true
      assert has_edge?(graph, :b, :d) == true
      assert has_edge?(graph, :c, :d) == true
      assert has_edge?(graph, :e, :d) == false
    end

    test "returns correct results in a complex graph" do
      graph =
        new()
        |> add_edge(:a, :b)
        |> add_edge(:a, :c)
        |> add_edge(:b, :d)
        |> add_edge(:c, :d)
        |> add_edge(:d, :e)
        |> add_edge(:f, :g)

      # Existing edges
      assert has_edge?(graph, :a, :b) == true
      assert has_edge?(graph, :a, :c) == true
      assert has_edge?(graph, :b, :d) == true
      assert has_edge?(graph, :c, :d) == true
      assert has_edge?(graph, :d, :e) == true
      assert has_edge?(graph, :f, :g) == true

      # Non-existing edges between existing vertices
      assert has_edge?(graph, :b, :a) == false
      assert has_edge?(graph, :c, :a) == false
      assert has_edge?(graph, :d, :b) == false
      assert has_edge?(graph, :d, :c) == false
      assert has_edge?(graph, :e, :d) == false
      assert has_edge?(graph, :g, :f) == false

      # Non-existing edges across components
      assert has_edge?(graph, :a, :f) == false
      assert has_edge?(graph, :b, :g) == false

      # Non-existing edges with non-existent vertices
      assert has_edge?(graph, :a, :x) == false
      assert has_edge?(graph, :x, :a) == false
      assert has_edge?(graph, :x, :y) == false
    end

    test "returns correct results in graph with cycles" do
      graph =
        new()
        |> add_edge(:a, :b)
        |> add_edge(:b, :c)
        |> add_edge(:c, :a)

      # Existing edges in the cycle
      assert has_edge?(graph, :a, :b) == true
      assert has_edge?(graph, :b, :c) == true
      assert has_edge?(graph, :c, :a) == true

      # Non-existing edges in the cycle
      assert has_edge?(graph, :a, :c) == false
      assert has_edge?(graph, :b, :a) == false
      assert has_edge?(graph, :c, :b) == false
    end
  end

  describe "has_vertex?/2" do
    test "returns false when graph is empty" do
      result = has_vertex?(new(), :a)

      assert result == false
    end

    test "returns false when vertex doesn't exist in non-empty graph" do
      result =
        new()
        |> add_vertex(:b)
        |> add_vertex(:c)
        |> has_vertex?(:a)

      assert result == false
    end

    test "returns true when vertex exists" do
      result =
        new()
        |> add_vertex(:a)
        |> has_vertex?(:a)

      assert result == true
    end
  end

  describe "incoming_edges/2" do
    test "returns empty list when vertex doesn't exist" do
      result = incoming_edges(new(), :a)

      assert result == []
    end

    test "returns empty list when vertex exists but has no edges" do
      result =
        new()
        |> add_vertex(:a)
        |> incoming_edges(:a)

      assert result == []
    end

    test "returns empty list when vertex has only outgoing edges" do
      result =
        new()
        |> add_edge(:a, :b)
        |> add_edge(:a, :c)
        |> incoming_edges(:a)

      assert result == []
    end

    test "returns incoming edge when vertex has one incoming edge" do
      result =
        new()
        |> add_edge(:a, :b)
        |> incoming_edges(:b)

      assert result == [{:a, :b}]
    end

    test "returns multiple incoming edges when vertex has multiple incoming edges" do
      result =
        new()
        |> add_edge(:a, :c)
        |> add_edge(:b, :c)
        |> add_edge(:d, :c)
        |> incoming_edges(:c)

      assert Enum.sort(result) == [{:a, :c}, {:b, :c}, {:d, :c}]
    end

    test "returns correct incoming edges in a complex graph" do
      graph =
        new()
        |> add_edge(:a, :b)
        |> add_edge(:a, :c)
        |> add_edge(:b, :d)
        |> add_edge(:c, :d)
        |> add_edge(:e, :b)
        |> add_edge(:f, :g)

      result_a = incoming_edges(graph, :a)
      assert result_a == []

      result_b = incoming_edges(graph, :b)
      assert Enum.sort(result_b) == [{:a, :b}, {:e, :b}]

      result_c = incoming_edges(graph, :c)
      assert result_c == [{:a, :c}]

      result_d = incoming_edges(graph, :d)
      assert Enum.sort(result_d) == [{:b, :d}, {:c, :d}]

      result_e = incoming_edges(graph, :e)
      assert result_e == []

      result_f = incoming_edges(graph, :f)
      assert result_f == []

      result_g = incoming_edges(graph, :g)
      assert result_g == [{:f, :g}]
    end
  end

  describe "new/0" do
    test "creates a new digraph" do
      result = new()

      assert result == %Digraph{vertices: %{}, outgoing_edges: %{}, incoming_edges: %{}}
    end
  end

  describe "reachable/2" do
    test "handles empty starting vertices list" do
      result =
        new()
        |> add_edge(:a, :b)
        |> add_edge(:b, :c)
        |> reachable([])

      assert result == []
    end

    test "returns empty list when graph is empty" do
      result = reachable(new(), [:a])

      assert result == []
    end

    test "returns empty list when starting vertices don't exist in non-empty graph" do
      result =
        new()
        |> add_edge(:a, :b)
        |> add_edge(:b, :c)
        |> reachable([:x])

      assert result == []
    end

    test "returns only the starting vertex itself when it has no outgoing edges" do
      result =
        new()
        |> add_vertex(:a)
        |> reachable([:a])

      assert result == [:a]
    end

    test "returns starting vertex and its direct neighbors" do
      result =
        new()
        |> add_edge(:a, :b)
        |> add_edge(:a, :c)
        |> reachable([:a])

      assert Enum.sort(result) == [:a, :b, :c]
    end

    test "returns all vertices in a linear chain" do
      result =
        new()
        |> add_edge(:a, :b)
        |> add_edge(:b, :c)
        |> add_edge(:c, :d)
        |> reachable([:a])

      assert Enum.sort(result) == [:a, :b, :c, :d]
    end

    test "returns only reachable part of linear chain when starting from middle" do
      result =
        new()
        |> add_edge(:a, :b)
        |> add_edge(:b, :c)
        |> add_edge(:c, :d)
        |> reachable([:b])

      assert Enum.sort(result) == [:b, :c, :d]
    end

    test "handles cycles correctly" do
      result =
        new()
        |> add_edge(:a, :b)
        |> add_edge(:b, :c)
        |> add_edge(:c, :a)
        |> reachable([:a])

      assert Enum.sort(result) == [:a, :b, :c]
    end

    test "handles self-loops" do
      result =
        new()
        |> add_edge(:a, :a)
        |> add_edge(:a, :b)
        |> reachable([:a])

      assert Enum.sort(result) == [:a, :b]
    end

    test "returns only connected component in disconnected graph" do
      result =
        new()
        |> add_edge(:a, :b)
        |> add_edge(:b, :c)
        # disconnected component
        |> add_edge(:x, :y)
        |> add_edge(:y, :z)
        |> reachable([:a])

      assert Enum.sort(result) == [:a, :b, :c]
    end

    test "handles complex graph with multiple paths" do
      result =
        new()
        |> add_edge(:a, :b)
        |> add_edge(:a, :c)
        |> add_edge(:b, :d)
        |> add_edge(:c, :d)
        |> add_edge(:d, :e)
        |> add_edge(:b, :f)
        |> reachable([:a])

      assert Enum.sort(result) == [:a, :b, :c, :d, :e, :f]
    end

    test "handles graph with cycles and multiple entry points" do
      result =
        new()
        |> add_edge(:a, :b)
        |> add_edge(:b, :c)
        # cycle b -> c -> b
        |> add_edge(:c, :b)
        |> add_edge(:a, :d)
        |> add_edge(:d, :e)
        # another path to the cycle
        |> add_edge(:e, :c)
        |> reachable([:a])

      assert Enum.sort(result) == [:a, :b, :c, :d, :e]
    end

    test "returns only isolated vertex when it has no connections" do
      result =
        new()
        |> add_vertex(:a)
        # other vertices with connections
        |> add_edge(:b, :c)
        |> add_edge(:c, :d)
        |> reachable([:a])

      assert result == [:a]
    end

    test "handles multiple starting vertices" do
      result =
        new()
        |> add_edge(:a, :b)
        |> add_edge(:b, :c)
        |> add_edge(:x, :y)
        |> add_edge(:y, :z)
        |> reachable([:a, :x])

      assert Enum.sort(result) == [:a, :b, :c, :x, :y, :z]
    end

    test "handles multiple starting vertices with overlapping reachable sets" do
      result =
        new()
        |> add_edge(:a, :shared)
        |> add_edge(:b, :shared)
        |> add_edge(:shared, :target)
        |> reachable([:a, :b])

      assert Enum.sort(result) == [:a, :b, :shared, :target]
    end

    test "ignores non-existent vertices in starting list" do
      result =
        new()
        |> add_edge(:a, :b)
        |> add_edge(:b, :c)
        |> reachable([:a, :nonexistent, :also_nonexistent])

      assert Enum.sort(result) == [:a, :b, :c]
    end

    test "returns empty list when all starting vertices are non-existent" do
      result =
        new()
        |> add_edge(:a, :b)
        |> add_edge(:b, :c)
        |> reachable([:nonexistent, :also_nonexistent])

      assert result == []
    end
  end

  describe "remove_vertex/2" do
    test "handles a vertex that doesn't exist" do
      result = remove_vertex(new(), :a)

      assert result == %Digraph{
               vertices: %{},
               outgoing_edges: %{},
               incoming_edges: %{}
             }
    end

    test "removes a vertex with no edges" do
      result =
        new()
        |> add_vertex(:a)
        |> remove_vertex(:a)

      assert result == %Digraph{
               vertices: %{},
               outgoing_edges: %{},
               incoming_edges: %{}
             }
    end

    test "removes a vertex that has outgoing edges only" do
      result =
        new()
        |> add_edge(:a, :b)
        |> add_edge(:a, :c)
        |> remove_vertex(:a)

      assert result == %Digraph{
               vertices: %{b: true, c: true},
               outgoing_edges: %{},
               incoming_edges: %{}
             }
    end

    test "removes a vertex that has incoming edges only" do
      result =
        new()
        |> add_edge(:a, :c)
        |> add_edge(:b, :c)
        |> remove_vertex(:c)

      assert result == %Digraph{
               vertices: %{a: true, b: true},
               outgoing_edges: %{},
               incoming_edges: %{}
             }
    end

    test "removes a vertex that has both incoming and outgoing edges" do
      result =
        new()
        |> add_edge(:a, :b)
        |> add_edge(:b, :c)
        |> remove_vertex(:b)

      assert result == %Digraph{
               vertices: %{a: true, c: true},
               outgoing_edges: %{},
               incoming_edges: %{}
             }
    end

    test "removes a vertex from a complex graph" do
      result =
        new()
        |> add_edge(:a, :b)
        |> add_edge(:a, :h)
        |> add_edge(:b, :c)
        |> add_edge(:b, :i)
        |> add_edge(:c, :d)
        |> add_edge(:e, :b)
        |> add_edge(:f, :g)
        |> remove_vertex(:b)

      assert result == %Digraph{
               vertices: %{a: true, c: true, d: true, e: true, f: true, g: true, h: true, i: true},
               outgoing_edges: %{a: %{h: true}, c: %{d: true}, f: %{g: true}},
               incoming_edges: %{d: %{c: true}, g: %{f: true}, h: %{a: true}}
             }
    end
  end

  describe "remove_vertices/2" do
    test "handles empty list of vertices" do
      result =
        new()
        |> add_edge(:a, :b)
        |> remove_vertices([])

      assert result == %Digraph{
               vertices: %{a: true, b: true},
               outgoing_edges: %{a: %{b: true}},
               incoming_edges: %{b: %{a: true}}
             }
    end

    test "handles vertices that don't exist" do
      result = remove_vertices(new(), [:a, :b])

      assert result == %Digraph{
               vertices: %{},
               outgoing_edges: %{},
               incoming_edges: %{}
             }
    end

    test "removes vertices with no edges" do
      result =
        new()
        |> add_vertices([:a, :b])
        |> remove_vertices([:a, :b])

      assert result == %Digraph{
               vertices: %{},
               outgoing_edges: %{},
               incoming_edges: %{}
             }
    end

    test "removes vertices that have outgoing edges only" do
      result =
        new()
        |> add_edge(:a1, :b1)
        |> add_edge(:a1, :c1)
        |> add_edge(:a2, :b2)
        |> add_edge(:a2, :c2)
        |> remove_vertices([:a1, :a2])

      assert result == %Digraph{
               vertices: %{b1: true, b2: true, c1: true, c2: true},
               outgoing_edges: %{},
               incoming_edges: %{}
             }
    end

    test "removes vertices that have incoming edges only" do
      result =
        new()
        |> add_edge(:a1, :c1)
        |> add_edge(:b1, :c1)
        |> add_edge(:a2, :c2)
        |> add_edge(:b2, :c2)
        |> remove_vertices([:c1, :c2])

      assert result == %Digraph{
               vertices: %{a1: true, a2: true, b1: true, b2: true},
               outgoing_edges: %{},
               incoming_edges: %{}
             }
    end

    test "removes vertices that have both incoming and outgoing edges" do
      result =
        new()
        |> add_edge(:a1, :b1)
        |> add_edge(:b1, :c1)
        |> add_edge(:a2, :b2)
        |> add_edge(:b2, :c2)
        |> remove_vertices([:b1, :b2])

      assert result == %Digraph{
               vertices: %{a1: true, a2: true, c1: true, c2: true},
               outgoing_edges: %{},
               incoming_edges: %{}
             }
    end

    test "removes vertices from a complex graph" do
      result =
        new()
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

      assert result == %Digraph{
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

  describe "shortest_path/3" do
    test "returns nil when graph is empty" do
      result = shortest_path(new(), :a, :b)

      assert result == nil
    end

    test "returns nil when source vertex doesn't exist" do
      result =
        new()
        |> add_vertex(:b)
        |> shortest_path(:a, :b)

      assert result == nil
    end

    test "returns nil when target vertex doesn't exist" do
      result =
        new()
        |> add_vertex(:a)
        |> shortest_path(:a, :b)

      assert result == nil
    end

    test "returns nil when neither vertex exists" do
      result =
        new()
        |> add_vertex(:c)
        |> shortest_path(:a, :b)

      assert result == nil
    end

    test "returns single-element list when source equals target" do
      result =
        new()
        |> add_vertex(:a)
        |> shortest_path(:a, :a)

      assert result == [:a]
    end

    test "returns nil when source equals target but vertex doesn't exist" do
      result = shortest_path(new(), :a, :a)

      assert result == nil
    end

    test "returns direct path when vertices are directly connected" do
      result =
        new()
        |> add_edge(:a, :b)
        |> shortest_path(:a, :b)

      assert result == [:a, :b]
    end

    test "returns nil when vertices exist but no path exists" do
      result =
        new()
        |> add_vertex(:a)
        |> add_vertex(:b)
        |> shortest_path(:a, :b)

      assert result == nil
    end

    test "returns nil for reverse direction when only forward edge exists" do
      result =
        new()
        |> add_edge(:a, :b)
        |> shortest_path(:b, :a)

      assert result == nil
    end

    test "returns path through linear chain" do
      result =
        new()
        |> add_edge(:a, :b)
        |> add_edge(:b, :c)
        |> add_edge(:c, :d)
        |> shortest_path(:a, :d)

      assert result == [:a, :b, :c, :d]
    end

    test "returns partial path in linear chain when starting from middle" do
      result =
        new()
        |> add_edge(:a, :b)
        |> add_edge(:b, :c)
        |> add_edge(:c, :d)
        |> shortest_path(:b, :d)

      assert result == [:b, :c, :d]
    end

    test "returns shortest path when multiple paths exist" do
      result =
        new()
        |> add_edge(:a, :b)
        |> add_edge(:b, :c)
        |> add_edge(:c, :d)
        # Shorter path
        |> add_edge(:a, :e)
        |> add_edge(:e, :d)
        |> shortest_path(:a, :d)

      assert result == [:a, :e, :d]
    end

    test "returns shortest path in diamond graph" do
      result =
        new()
        |> add_edge(:a, :b)
        |> add_edge(:a, :c)
        |> add_edge(:b, :d)
        |> add_edge(:c, :d)
        |> shortest_path(:a, :d)

      # Both paths have same length, should return one of them
      assert result in [[:a, :b, :d], [:a, :c, :d]]
    end

    test "handles cycles correctly" do
      result =
        new()
        |> add_edge(:a, :b)
        |> add_edge(:b, :c)
        |> add_edge(:c, :a)
        |> shortest_path(:a, :c)

      assert result == [:a, :b, :c]
    end

    test "handles self-loop at source" do
      result =
        new()
        |> add_edge(:a, :a)
        |> add_edge(:a, :b)
        |> shortest_path(:a, :b)

      assert result == [:a, :b]
    end

    test "handles self-loop at target" do
      result =
        new()
        |> add_edge(:a, :b)
        |> add_edge(:b, :b)
        |> shortest_path(:a, :b)

      assert result == [:a, :b]
    end

    test "handles self-loop in the middle of path" do
      result =
        new()
        |> add_edge(:a, :b)
        |> add_edge(:b, :b)
        |> add_edge(:b, :c)
        |> shortest_path(:a, :c)

      assert result == [:a, :b, :c]
    end

    test "returns nil when path is blocked by disconnected component" do
      result =
        new()
        |> add_edge(:a, :b)
        # Disconnected component
        |> add_edge(:x, :y)
        |> shortest_path(:a, :y)

      assert result == nil
    end

    test "finds path within one component of disconnected graph" do
      result =
        new()
        |> add_edge(:a, :b)
        |> add_edge(:b, :c)
        # Disconnected component
        |> add_edge(:x, :y)
        |> add_edge(:y, :z)
        |> shortest_path(:a, :c)

      assert result == [:a, :b, :c]
    end

    test "finds path through multiple possible routes" do
      result =
        new()
        |> add_edge(:start, :a)
        |> add_edge(:start, :b)
        |> add_edge(:start, :c)
        |> add_edge(:a, :middle)
        |> add_edge(:b, :middle)
        |> add_edge(:c, :middle)
        |> add_edge(:middle, :end)
        |> shortest_path(:start, :end)

      # All paths have same length (3), should return one of them
      assert result in [
               [:start, :a, :middle, :end],
               [:start, :b, :middle, :end],
               [:start, :c, :middle, :end]
             ]
    end

    test "handles bidirectional edge scenario" do
      result =
        new()
        |> add_edge(:a, :b)
        |> add_edge(:b, :a)
        |> add_edge(:b, :c)
        |> shortest_path(:a, :c)

      assert result == [:a, :b, :c]
    end
  end

  describe "sorted_edges/1" do
    test "lists edges in sorted order" do
      result =
        new()
        |> add_edges([{:b, :c}, {:a, :b}, {:d, :e}, {:d, :f}])
        |> sorted_edges()

      assert result == [{:a, :b}, {:b, :c}, {:d, :e}, {:d, :f}]
    end
  end

  describe "sorted_vertices/1" do
    test "lists vertices in sorted order" do
      result =
        new()
        |> add_vertices([:c, :a, :b])
        |> sorted_vertices()

      assert result == [:a, :b, :c]
    end
  end

  describe "vertices/1" do
    test "returns empty list for empty graph" do
      result = vertices(new())

      assert result == []
    end

    test "returns vertices when graph has only vertices (no edges)" do
      result =
        new()
        |> add_vertices([:a, :b, :c])
        |> vertices()

      assert Enum.sort(result) == [:a, :b, :c]
    end

    test "returns vertices when graph has vertices and edges" do
      result =
        new()
        |> add_edge(:a, :b)
        |> add_edge(:b, :c)
        |> add_vertex(:d)
        |> vertices()

      assert Enum.sort(result) == [:a, :b, :c, :d]
    end
  end
end
