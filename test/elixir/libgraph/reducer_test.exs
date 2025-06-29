defmodule Graph.Reducer.Test do
  use ExUnit.Case, async: true
  doctest Graph.Reducers.Bfs
  doctest Graph.Reducers.Dfs

  test "can walk a graph depth-first" do
    g =
      Graph.new()
      |> Graph.add_vertices([:a, :b, :c, :d, :e, :f, :g])
      |> Graph.add_edge(:a, :b)
      |> Graph.add_edge(:b, :c)
      |> Graph.add_edge(:b, :d)
      |> Graph.add_edge(:c, :e)
      |> Graph.add_edge(:d, :f)
      |> Graph.add_edge(:f, :g)

    expected = [:a, :b, :c, :e, :d, :f, :g]
    assert ^expected = Graph.Reducers.Dfs.map(g, fn v -> v end)
  end

  test "can walk a graph breadth-first" do
    g =
      Graph.new()
      |> Graph.add_vertices([:a, :b, :c, :d, :e, :f, :g])
      |> Graph.add_edge(:a, :b)
      |> Graph.add_edge(:a, :d)
      |> Graph.add_edge(:b, :c)
      |> Graph.add_edge(:b, :d)
      |> Graph.add_edge(:c, :e)
      |> Graph.add_edge(:d, :f)
      |> Graph.add_edge(:f, :g)

    expected = [:a, :b, :d, :c, :f, :e, :g]
    assert ^expected = Graph.Reducers.Bfs.map(g, fn v -> v end)
  end

  test "can walk a graph breadth-first, when the starting points had their in-edges deleted" do
    g =
      Graph.new()
      |> Graph.add_vertices([:a, :b, :c, :d, :e, :f, :g])
      |> Graph.add_edge(:a, :b)
      |> Graph.add_edge(:a, :d)
      |> Graph.add_edge(:b, :c)
      |> Graph.add_edge(:b, :d)
      |> Graph.add_edge(:c, :e)
      |> Graph.add_edge(:d, :f)
      |> Graph.add_edge(:f, :g)
      # Add this edge and then remove it
      |> Graph.add_edge(:b, :a)
      |> Graph.delete_edge(:b, :a)

    expected = [:a, :b, :d, :c, :f, :e, :g]
    assert ^expected = Graph.Reducers.Bfs.map(g, fn v -> v end)
  end
end
