defmodule Hologram.Compiler.DigraphTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Digraph
  alias Hologram.Compiler.Digraph

  setup do
    [empty_graph: new()]
  end

  describe "add_vertex/2" do
    test "adds a single vertex", %{empty_graph: graph} do
      result = add_vertex(graph, :a)
      assert result == graph

      vertices_table = graph.vertices_table

      assert :ets.member(vertices_table, :a)
      refute :ets.member(vertices_table, :b)

      # Also verify the stored format
      assert :ets.lookup(vertices_table, :a) == [{:a}]
      assert :ets.lookup(vertices_table, :b) == []
    end
  end

  describe "add_vertices/2" do
    test "adds multiple vertices", %{empty_graph: graph} do
      result = add_vertices(graph, [:a, :b])
      assert result == graph

      vertices_table = graph.vertices_table

      assert :ets.member(vertices_table, :a)
      assert :ets.member(vertices_table, :b)
      refute :ets.member(vertices_table, :c)

      # Also verify the stored format
      assert :ets.lookup(vertices_table, :a) == [{:a}]
      assert :ets.lookup(vertices_table, :b) == [{:b}]
      assert :ets.lookup(vertices_table, :c) == []
    end
  end

  describe "add_edge/3" do
    test "adds a single edge", %{empty_graph: graph} do
      result = add_edge(graph, :a, :b)
      assert result == graph

      vertices_table = graph.vertices_table

      assert :ets.member(vertices_table, :a)
      assert :ets.member(vertices_table, :b)
      refute :ets.member(vertices_table, :c)

      # Also verify the stored format
      assert :ets.lookup(vertices_table, :a) == [{:a}]
      assert :ets.lookup(vertices_table, :b) == [{:b}]
      assert :ets.lookup(vertices_table, :c) == []

      edges_table = graph.edges_table

      assert :ets.member(edges_table, :a)
      refute :ets.member(edges_table, :b)
      refute :ets.member(edges_table, :c)

      # Also verify the stored format
      assert :ets.lookup(edges_table, :a) == [{:a, :b}]
      assert :ets.lookup(edges_table, :b) == []
      assert :ets.lookup(edges_table, :c) == []

      reverse_edges_table = graph.reverse_edges_table

      refute :ets.member(reverse_edges_table, :a)
      assert :ets.member(reverse_edges_table, :b)
      refute :ets.member(reverse_edges_table, :c)

      # Also verify the stored format
      assert :ets.lookup(reverse_edges_table, :a) == []
      assert :ets.lookup(reverse_edges_table, :b) == [{:b, :a}]
      assert :ets.lookup(reverse_edges_table, :c) == []
    end

    test "adds edge to a vertex that is already a source of another edge", %{empty_graph: graph} do
      result_1 = add_edge(graph, :a, :b)
      result_2 = add_edge(graph, :a, :c)

      assert result_1 == graph
      assert result_2 == graph

      vertices_table = graph.vertices_table

      assert :ets.member(vertices_table, :a)
      assert :ets.member(vertices_table, :b)
      assert :ets.member(vertices_table, :c)
      refute :ets.member(vertices_table, :d)

      # Also verify the stored format
      assert :ets.lookup(vertices_table, :a) == [{:a}]
      assert :ets.lookup(vertices_table, :b) == [{:b}]
      assert :ets.lookup(vertices_table, :c) == [{:c}]
      assert :ets.lookup(vertices_table, :d) == []

      edges_table = graph.edges_table

      assert :ets.member(edges_table, :a)
      refute :ets.member(edges_table, :b)
      refute :ets.member(edges_table, :c)
      refute :ets.member(edges_table, :d)

      # Also verify the stored format

      edges_from_a = :ets.lookup(edges_table, :a)
      assert Enum.sort(edges_from_a) == [{:a, :b}, {:a, :c}]

      assert :ets.lookup(edges_table, :b) == []
      assert :ets.lookup(edges_table, :c) == []
      assert :ets.lookup(edges_table, :d) == []

      reverse_edges_table = graph.reverse_edges_table

      refute :ets.member(reverse_edges_table, :a)
      assert :ets.member(reverse_edges_table, :b)
      assert :ets.member(reverse_edges_table, :c)
      refute :ets.member(reverse_edges_table, :d)

      # Also verify the stored format
      assert :ets.lookup(reverse_edges_table, :a) == []
      assert :ets.lookup(reverse_edges_table, :b) == [{:b, :a}]
      assert :ets.lookup(reverse_edges_table, :c) == [{:c, :a}]
      assert :ets.lookup(reverse_edges_table, :d) == []
    end
  end

  describe "add_edges/2" do
    test "adds multiple edges", %{empty_graph: graph} do
      result = add_edges(graph, [{:a, :b}, {:b, :c}, {:d, :e}, {:d, :f}])
      assert result == graph

      vertices_table = graph.vertices_table

      assert :ets.member(vertices_table, :a)
      assert :ets.member(vertices_table, :b)
      assert :ets.member(vertices_table, :c)
      assert :ets.member(vertices_table, :d)
      assert :ets.member(vertices_table, :e)
      assert :ets.member(vertices_table, :f)
      refute :ets.member(vertices_table, :g)

      # Also verify the stored format
      assert :ets.lookup(vertices_table, :a) == [{:a}]
      assert :ets.lookup(vertices_table, :b) == [{:b}]
      assert :ets.lookup(vertices_table, :c) == [{:c}]
      assert :ets.lookup(vertices_table, :d) == [{:d}]
      assert :ets.lookup(vertices_table, :e) == [{:e}]
      assert :ets.lookup(vertices_table, :f) == [{:f}]
      assert :ets.lookup(vertices_table, :g) == []

      edges_table = graph.edges_table

      assert :ets.member(edges_table, :a)
      assert :ets.member(edges_table, :b)
      refute :ets.member(edges_table, :c)
      assert :ets.member(edges_table, :d)
      refute :ets.member(edges_table, :e)
      refute :ets.member(edges_table, :f)
      refute :ets.member(edges_table, :g)

      # Also verify the stored format

      assert :ets.lookup(edges_table, :a) == [{:a, :b}]
      assert :ets.lookup(edges_table, :b) == [{:b, :c}]
      assert :ets.lookup(edges_table, :c) == []

      edges_from_d =
        edges_table
        |> :ets.lookup(:d)
        |> Enum.sort()

      assert edges_from_d == [{:d, :e}, {:d, :f}]

      assert :ets.lookup(edges_table, :e) == []
      assert :ets.lookup(edges_table, :f) == []
      assert :ets.lookup(edges_table, :g) == []

      reverse_edges_table = graph.reverse_edges_table

      refute :ets.member(reverse_edges_table, :a)
      assert :ets.member(reverse_edges_table, :b)
      assert :ets.member(reverse_edges_table, :c)
      refute :ets.member(reverse_edges_table, :d)
      assert :ets.member(reverse_edges_table, :e)
      assert :ets.member(reverse_edges_table, :f)
      refute :ets.member(reverse_edges_table, :g)

      # Also verify the stored format
      assert :ets.lookup(reverse_edges_table, :a) == []
      assert :ets.lookup(reverse_edges_table, :b) == [{:b, :a}]
      assert :ets.lookup(reverse_edges_table, :c) == [{:c, :b}]
      assert :ets.lookup(reverse_edges_table, :d) == []
      assert :ets.lookup(reverse_edges_table, :e) == [{:e, :d}]
      assert :ets.lookup(reverse_edges_table, :f) == [{:f, :d}]
      assert :ets.lookup(reverse_edges_table, :g) == []
    end
  end

  describe "edges/1" do
    test "lists edges", %{empty_graph: graph} do
      result =
        graph
        |> add_edges([{:b, :c}, {:a, :b}, {:d, :e}, {:d, :f}])
        |> edges()

      assert Enum.sort(result) == [{:a, :b}, {:b, :c}, {:d, :e}, {:d, :f}]
    end
  end

  describe "has_edge?/3" do
    test "returns false when there is no edge between two vertices", %{empty_graph: graph} do
      add_vertices(graph, [:a, :b])

      refute has_edge?(graph, :a, :b)
      refute has_edge?(graph, :b, :a)
    end

    test "returns true when there is an edge between two vertices", %{empty_graph: graph} do
      add_edge(graph, :a, :b)

      assert has_edge?(graph, :a, :b)
      refute has_edge?(graph, :b, :a)
    end

    test "returns false when source vertex doesn't exist", %{empty_graph: graph} do
      add_vertex(graph, :b)

      refute has_edge?(graph, :a, :b)
    end

    test "returns false when target vertex doesn't exist", %{empty_graph: graph} do
      add_vertex(graph, :a)

      refute has_edge?(graph, :a, :b)
    end

    test "returns false when neither vertex exists", %{empty_graph: graph} do
      refute has_edge?(graph, :a, :b)
    end

    test "returns false when source has edges but not to the target", %{empty_graph: graph} do
      add_edges(graph, [{:a, :b}, {:a, :c}])

      assert has_edge?(graph, :a, :b)
      assert has_edge?(graph, :a, :c)
      refute has_edge?(graph, :a, :d)
    end

    test "returns true when source has multiple edges including one to target", %{
      empty_graph: graph
    } do
      add_edges(graph, [{:a, :b}, {:a, :c}, {:a, :d}])

      assert has_edge?(graph, :a, :b)
      assert has_edge?(graph, :a, :c)
      assert has_edge?(graph, :a, :d)
      refute has_edge?(graph, :a, :e)
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

  describe "sorted_edges/1" do
    test "lists edges in sorted order", %{empty_graph: graph} do
      result =
        graph
        |> add_edges([{:b, :c}, {:a, :b}, {:d, :e}, {:d, :f}])
        |> sorted_edges()

      assert result == [{:a, :b}, {:b, :c}, {:d, :e}, {:d, :f}]
    end
  end

  describe "sorted_vertices/1" do
    test "lists vertices in sorted order", %{empty_graph: graph} do
      result =
        graph
        |> add_vertices([:c, :a, :b])
        |> sorted_vertices()

      assert result == [:a, :b, :c]
    end
  end

  describe "vertices/1" do
    test "lists vertices", %{empty_graph: graph} do
      result =
        graph
        |> add_vertices([:c, :a, :b])
        |> vertices()

      assert Enum.sort(result) == [:a, :b, :c]
    end
  end
end
