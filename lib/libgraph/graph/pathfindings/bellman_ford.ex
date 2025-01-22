defmodule Graph.Pathfindings.BellmanFord do
  @moduledoc false

  # The Bellman–Ford algorithm is an algorithm that computes shortest paths from a single
  # source vertex to all of the other vertices in a weighted digraph.
  # It is capable of handling graphs in which some of the edge weights are negative numbers
  # Time complexity: O(VLogV)

  @typep distance() :: %{Graph.vertex_id() => integer()}

  @doc """
  Returns nil when graph has negative cycle.
  """
  @spec call(Graph.t(), Graph.vertex()) :: %{Graph.vertex() => integer() | :infinity} | nil
  def call(%Graph{vertices: vs, edges: meta} = g, a) do
    distances = a |> Graph.Utils.vertex_id() |> init_distances(vs)

    weights = Enum.map(meta, &edge_weight/1)

    distances =
      for _ <- 1..map_size(vs),
          edge <- weights,
          reduce: distances do
        acc -> update_distance(edge, acc)
      end

    if has_negative_cycle?(distances, weights) do
      nil
    else
      Map.new(distances, fn {k, v} -> {Map.fetch!(g.vertices, k), v} end)
    end
  end

  @spec init_distances(Graph.vertex(), Graph.vertices()) :: distance
  defp init_distances(vertex_id, vertices) do
    Map.new(vertices, fn
      {id, _vertex} when id == vertex_id -> {id, 0}
      {id, _} -> {id, :infinity}
    end)
  end

  @spec update_distance(term, distance) :: distance
  defp update_distance({{u, v}, weight}, distances) do
    %{^u => du, ^v => dv} = distances

    if du != :infinity and du + weight < dv do
      %{distances | v => du + weight}
    else
      distances
    end
  end

  @spec edge_weight(term) :: float
  defp edge_weight({e, edge_value}), do: {e, edge_value |> Map.values() |> List.first()}

  defp has_negative_cycle?(distances, meta) do
    Enum.any?(meta, fn {{u, v}, weight} ->
      %{^u => du, ^v => dv} = distances

      du != :infinity and du + weight < dv
    end)
  end
end
