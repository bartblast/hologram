defmodule Graph.Test.Generators do
  @moduledoc false

  def dag(size) do
    dag(size, Graph.new())
  end

  defp dag(0, g) do
    g
  end

  defp dag(i, g) do
    i = i + 1
    g = Enum.reduce(0..i, g, fn v, g -> Graph.add_vertex(g, v) end)

    Enum.reduce(1..i, g, fn v, g ->
      if v + 1 > i do
        g
      else
        r = (v + 1)..i

        Stream.iterate(Enum.random(r), fn _ -> Enum.random(r) end)
        |> Enum.take(3)
        |> Enum.reduce(g, fn v2, acc ->
          Graph.add_edge(acc, v, v2)
        end)
      end
    end)
  end

  def biased_dag(size) do
    g = dag(size, Graph.new())
    paths = Graph.get_paths(g, 1, size)
    [shortest | _] = Enum.sort_by(paths, &length(&1))
    path_len = length(shortest)

    shortest =
      shortest
      |> Stream.with_index()
      |> Stream.map(fn {v, i} -> {i, v} end)
      |> Enum.into(%{})

    Enum.reduce(shortest, g, fn
      {i, v}, acc ->
        Graph.label_vertex(acc, v, path_len - i)
    end)
  end

  def libgraph_to_digraph(%Graph{vertices: vs, out_edges: es}) do
    dg = :digraph.new()
    for {_, v} <- vs, do: :digraph.add_vertex(dg, v)

    for {v_id, v_out} <- es, v2_id <- v_out do
      v = Map.get(vs, v_id)
      v2 = Map.get(vs, v2_id)
      :digraph.add_edge(dg, v, v2)
    end

    dg
  end
end
