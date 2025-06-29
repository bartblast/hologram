defmodule Hologram.Compiler.Digraph2 do
  @moduledoc false

  alias Hologram.Compiler.Digraph2

  defstruct [:vertices, :edges, :reverse_edges]

  @type t :: %__MODULE__{
          vertices: %{any => boolean},
          edges: %{any => %{any => boolean}},
          reverse_edges: %{any => %{any => boolean}}
        }

  @type edge :: {vertex, vertex}
  @type vertex :: any

  @doc """
  Adds a vertex to the graph.
  """
  @spec add_vertex(t, vertex) :: t
  def add_vertex(%Digraph2{vertices: vertices} = graph, vertex) do
    %{graph | vertices: Map.put(vertices, vertex, true)}
  end

  @doc """
  Adds multiple vertices to the graph.
  """
  @spec add_vertices(t, [vertex]) :: t
  def add_vertices(%Digraph2{vertices: old_vertices} = graph, added_vertices) do
    new_vertices =
      Enum.reduce(added_vertices, old_vertices, fn vertex, acc ->
        Map.put(acc, vertex, true)
      end)

    %{graph | vertices: new_vertices}
  end

  @doc """
  Adds an edge from source to target vertex.
  Automatically adds vertices if they don't exist.
  """
  @spec add_edge(t, vertex, vertex) :: t
  def add_edge(
        %Digraph2{vertices: vertices, edges: edges, reverse_edges: reverse_edges},
        source,
        target
      ) do
    new_vertices =
      vertices
      |> Map.put(source, true)
      |> Map.put(target, true)

    targets =
      edges
      |> Map.get(source, %{})
      |> Map.put(target, true)

    new_edges = Map.put(edges, source, targets)

    sources =
      reverse_edges
      |> Map.get(target, %{})
      |> Map.put(source, true)

    new_reverse_edges = Map.put(reverse_edges, target, sources)

    %Digraph2{vertices: new_vertices, edges: new_edges, reverse_edges: new_reverse_edges}
  end

  @doc """
  Creates a new directed graph.
  """
  @spec new :: t
  def new do
    %Digraph2{vertices: %{}, edges: %{}, reverse_edges: %{}}
  end
end
