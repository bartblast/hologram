defmodule Graph.Test.Fixtures.Parser do
  @moduledoc false

  @doc """
  Given a path to one of the test fixture files which store
  graphs as lines of tab-separated points representing the edges.
  Each edge is on it's own line. There may be comments which lead with `#`.
  """
  @spec parse(String.t()) :: Graph.t()
  @spec parse(String.t(), :directed | :undirected) :: Graph.t()
  def parse(path, type \\ :undirected) do
    g = Graph.new(type: type)

    points =
      path
      |> File.stream!()
      |> Stream.reject(fn
        <<c::utf8, _::binary>> -> c in [?\#, ?\%]
        _ -> false
      end)
      |> Stream.map(fn line -> String.split(line, ~r/[\t\s\n]/, trim: true) end)
      |> Stream.map(fn [a, b] -> {String.to_integer(a), String.to_integer(b)} end)

    Graph.add_edges(g, points)
  end
end
