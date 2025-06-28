defmodule Hologram.Compiler.Digraph do
  @moduledoc false
  # A high-performance directed graph implementation optimized for large datasets
  # and concurrent access. Uses ETS tables for storage.

  # This implementation stores:
  # - Vertices in an ETS set
  # - Edges in an ETS bag (allows duplicate edges with same source)
  # - Reverse edges in another ETS bag for efficient inbound edges queries

  alias Hologram.Compiler.Digraph

  defstruct [:vertices_table, :edges_table, :reverse_edges_table]

  @type t :: %__MODULE__{
          vertices_table: :ets.tid(),
          edges_table: :ets.tid(),
          reverse_edges_table: :ets.tid()
        }

  @type edge :: {vertex, vertex}
  @type vertex :: any

  @doc """
  Adds a vertex to the graph.
  """
  @spec add_vertex(t, vertex) :: t
  def add_vertex(%Digraph{vertices_table: vertices_table} = graph, vertex) do
    :ets.insert(vertices_table, {vertex})
    graph
  end

  @doc """
  Adds multiple vertices to the graph.
  """
  @spec add_vertices(t, [vertex]) :: t
  def add_vertices(%Digraph{vertices_table: vertices_table} = graph, vertices) do
    objects = Enum.map(vertices, &{&1})
    :ets.insert(vertices_table, objects)
    graph
  end

  @doc """
  Adds an edge from source to target vertex.
  Automatically adds vertices if they don't exist.
  """
  @spec add_edge(t, vertex, vertex) :: t
  def add_edge(
        %Digraph{
          vertices_table: vertices_table,
          edges_table: edges_table,
          reverse_edges_table: reverse_edges_table
        } = graph,
        source,
        target
      ) do
    :ets.insert(vertices_table, [{source}, {target}])

    :ets.insert(edges_table, {source, target})

    :ets.insert(reverse_edges_table, {target, source})

    graph
  end

  @doc """
  Adds multiple edges to the graph.
  """
  @spec add_edges(t, [edge]) :: t
  def add_edges(
        %Digraph{
          edges_table: edges_table,
          reverse_edges_table: reverse_edges_table
        } = graph,
        edges
      ) do
    vertices = Enum.reduce(edges, [], fn {source, target}, acc -> [source | [target | acc]] end)
    add_vertices(graph, vertices)

    :ets.insert(edges_table, edges)

    reverse_edges = Enum.map(edges, fn {source, target} -> {target, source} end)

    :ets.insert(reverse_edges_table, reverse_edges)

    graph
  end

  @doc """
  Returns all edges in the graph.
  """
  @spec edges(t) :: [edge]
  def edges(%Digraph{edges_table: edges_table}) do
    :ets.tab2list(edges_table)
  end

  @doc """
  Checks if an edge exists between source and target.
  """
  @spec has_edge?(t, vertex, vertex) :: boolean
  def has_edge?(%Digraph{edges_table: edges_table}, source, target) do
    case :ets.lookup(edges_table, source) do
      [] ->
        false

      edges_from_source ->
        Enum.any?(edges_from_source, fn {_source, t} -> t == target end)
    end
  end

  @doc """
  Creates a new directed graph.
  """
  @spec new :: t
  def new do
    vertices_table = :ets.new(:vertices, [:set, :public, {:read_concurrency, true}])
    edges_table = :ets.new(:edges, [:bag, :public, {:read_concurrency, true}])
    reverse_edges_table = :ets.new(:reverse_edges, [:bag, :public, {:read_concurrency, true}])

    %Digraph{
      vertices_table: vertices_table,
      edges_table: edges_table,
      reverse_edges_table: reverse_edges_table
    }
  end

  @doc """
  Returns all edges in the graph sorted in ascending order.
  """
  @spec sorted_edges(t) :: [edge]
  def sorted_edges(%Digraph{} = graph) do
    graph
    |> edges()
    |> Enum.sort()
  end

  @doc """
  Returns all vertices in the graph sorted in ascending order.
  """
  @spec sorted_vertices(t) :: [vertex]
  def sorted_vertices(%Digraph{} = graph) do
    graph
    |> vertices()
    |> Enum.sort()
  end

  @doc """
  Returns all vertices in the graph.
  """
  @spec vertices(t) :: [vertex]
  def vertices(%Digraph{vertices_table: vertices_table}) do
    :ets.select(vertices_table, [{{:"$1"}, [], [:"$1"]}])
  end
end
