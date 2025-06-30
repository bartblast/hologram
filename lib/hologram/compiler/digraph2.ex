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
  Adds multiple edges to the graph.
  """
  @spec add_edges(t, [edge]) :: t
  def add_edges(
        %Digraph2{vertices: vertices, edges: edges, reverse_edges: reverse_edges},
        added_edges
      ) do
    acc = {vertices, edges, reverse_edges}

    {new_vertices, new_edges, new_reverse_edges} =
      Enum.reduce(added_edges, acc, fn {source, target},
                                       {acc_vertices, acc_edges, acc_reverse_edges} ->
        new_acc_vertices =
          acc_vertices
          |> Map.put(source, true)
          |> Map.put(target, true)

        targets =
          acc_edges
          |> Map.get(source, %{})
          |> Map.put(target, true)

        new_acc_edges = Map.put(acc_edges, source, targets)

        sources =
          acc_reverse_edges
          |> Map.get(target, %{})
          |> Map.put(source, true)

        new_acc_reverse_edges = Map.put(acc_reverse_edges, target, sources)

        {new_acc_vertices, new_acc_edges, new_acc_reverse_edges}
      end)

    %Digraph2{vertices: new_vertices, edges: new_edges, reverse_edges: new_reverse_edges}
  end

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
  Creates a new directed graph.
  """
  @spec new :: t
  def new do
    %Digraph2{vertices: %{}, edges: %{}, reverse_edges: %{}}
  end

  @doc """
  Removes a vertex from the graph along with all edges connected to it.
  This includes both outgoing edges from the vertex and incoming edges to the vertex.
  """
  @spec remove_vertex(t, vertex) :: t
  def remove_vertex(
        %Digraph2{vertices: vertices, edges: outgoing_edges, reverse_edges: incoming_edges} =
          graph,
        vertex
      ) do
    # Capture the outgoing and incoming edges before removing them
    old_outgoing_targets = Map.get(outgoing_edges, vertex, %{})
    old_incoming_sources = Map.get(incoming_edges, vertex, %{})

    new_vertices = Map.delete(vertices, vertex)
    outgoing_edges_without_vertex = Map.delete(outgoing_edges, vertex)
    incoming_edges_without_vertex = Map.delete(incoming_edges, vertex)

    # Clean up edges: remove references to the removed vertex
    # from all vertices that pointed to it
    cleaned_outgoing_edges =
      Enum.reduce(old_incoming_sources, outgoing_edges_without_vertex, fn {source, _},
                                                                          acc_outgoing_edges ->
        case Map.get(acc_outgoing_edges, source) do
          nil ->
            acc_outgoing_edges

          targets ->
            cleaned_targets = Map.delete(targets, vertex)

            if map_size(cleaned_targets) == 0 do
              Map.delete(acc_outgoing_edges, source)
            else
              Map.put(acc_outgoing_edges, source, cleaned_targets)
            end
        end
      end)

    # Clean up reverse edges: remove references to the removed vertex
    # from all vertices it pointed to
    cleaned_incoming_edges =
      Enum.reduce(old_outgoing_targets, incoming_edges_without_vertex, fn {target, _},
                                                                          acc_incomming_edges ->
        case Map.get(acc_incomming_edges, target) do
          nil ->
            acc_incomming_edges

          sources ->
            cleaned_sources = Map.delete(sources, vertex)

            if map_size(cleaned_sources) == 0 do
              Map.delete(acc_incomming_edges, target)
            else
              Map.put(acc_incomming_edges, target, cleaned_sources)
            end
        end
      end)

    %{
      graph
      | vertices: new_vertices,
        edges: cleaned_outgoing_edges,
        reverse_edges: cleaned_incoming_edges
    }
  end
end
