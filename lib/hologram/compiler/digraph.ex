defmodule Hologram.Compiler.Digraph do
  @moduledoc false
  # A high-performance directed graph implementation optimized for large datasets
  # and concurrent access. Uses ETS tables for storage.

  # This implementation stores:
  # - Vertices in an ETS set
  # - Edges in an ETS bag (allows duplicate edges with same source)
  # - Reverse edges in another ETS bag for efficient inbound edges queries

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
  def add_vertex(%__MODULE__{vertices_table: vertices_table} = graph, vertex) do
    :ets.insert(vertices_table, {vertex})
    graph
  end

  @doc """
  Adds multiple vertices to the graph.
  """
  @spec add_vertices(t, [vertex]) :: t
  def add_vertices(%__MODULE__{vertices_table: vertices_table} = graph, vertices) do
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
        %__MODULE__{
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
        %__MODULE__{
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
  Creates a new directed graph.
  """
  @spec new :: t
  def new do
    vertices_table = :ets.new(:vertices, [:set, :public, {:read_concurrency, true}])
    edges_table = :ets.new(:edges, [:bag, :public, {:read_concurrency, true}])
    reverse_edges_table = :ets.new(:reverse_edges, [:bag, :public, {:read_concurrency, true}])

    %__MODULE__{
      vertices_table: vertices_table,
      edges_table: edges_table,
      reverse_edges_table: reverse_edges_table
    }
  end
end
