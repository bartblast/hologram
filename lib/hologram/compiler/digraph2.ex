defmodule Hologram.Compiler.Digraph2 do
  @moduledoc false

  alias Hologram.Compiler.Digraph2

  defstruct [:vertices, :outgoing_edges, :incoming_edges]

  @type t :: %__MODULE__{
          vertices: %{any => boolean},
          outgoing_edges: %{any => %{any => boolean}},
          incoming_edges: %{any => %{any => boolean}}
        }

  @type edge :: {vertex, vertex}
  @type vertex :: any

  @doc """
  Adds an edge from source to target vertex.
  Automatically adds vertices if they don't exist.
  """
  @spec add_edge(t, vertex, vertex) :: t
  def add_edge(graph, source, target) do
    %Digraph2{
      vertices: vertices,
      outgoing_edges: outgoing_edges,
      incoming_edges: incoming_edges
    } = graph

    new_vertices =
      vertices
      |> Map.put(source, true)
      |> Map.put(target, true)

    targets =
      outgoing_edges
      |> Map.get(source, %{})
      |> Map.put(target, true)

    new_outgoing_edges = Map.put(outgoing_edges, source, targets)

    sources =
      incoming_edges
      |> Map.get(target, %{})
      |> Map.put(source, true)

    new_incoming_edges = Map.put(incoming_edges, target, sources)

    %Digraph2{
      vertices: new_vertices,
      outgoing_edges: new_outgoing_edges,
      incoming_edges: new_incoming_edges
    }
  end

  @doc """
  Adds multiple edges to the graph.
  """
  @spec add_edges(t, [edge]) :: t
  # credo:disable-for-lines:41 Credo.Check.Refactor.ABCSize
  # The above Credo check is disabled because the function is optimised this way
  def add_edges(graph, added_edges) do
    %Digraph2{
      vertices: vertices,
      outgoing_edges: outgoing_edges,
      incoming_edges: incoming_edges
    } = graph

    acc = {vertices, outgoing_edges, incoming_edges}

    {new_vertices, new_outgoing_edges, new_incoming_edges} =
      Enum.reduce(added_edges, acc, fn {source, target},
                                       {acc_vertices, acc_outgoing_edges, acc_incoming_edges} ->
        new_acc_vertices =
          acc_vertices
          |> Map.put(source, true)
          |> Map.put(target, true)

        targets =
          acc_outgoing_edges
          |> Map.get(source, %{})
          |> Map.put(target, true)

        new_acc_outgoing_edges = Map.put(acc_outgoing_edges, source, targets)

        sources =
          acc_incoming_edges
          |> Map.get(target, %{})
          |> Map.put(source, true)

        new_acc_incoming_edges = Map.put(acc_incoming_edges, target, sources)

        {new_acc_vertices, new_acc_outgoing_edges, new_acc_incoming_edges}
      end)

    %Digraph2{
      vertices: new_vertices,
      outgoing_edges: new_outgoing_edges,
      incoming_edges: new_incoming_edges
    }
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
    %Digraph2{vertices: %{}, outgoing_edges: %{}, incoming_edges: %{}}
  end

  @doc """
  Removes a vertex from the graph along with all edges connected to it.
  This includes both outgoing edges from the vertex and incoming edges to the vertex.
  """
  @spec remove_vertex(t, vertex) :: t
  # credo:disable-for-lines:63 /Credo.Check.Refactor.ABCSize|Credo.Check.Refactor.Nesting/
  # The above Credo checks are disabled because the function is optimised this way
  def remove_vertex(graph, vertex) do
    %Digraph2{
      vertices: vertices,
      outgoing_edges: outgoing_edges,
      incoming_edges: incoming_edges
    } = graph

    # Capture the outgoing and incoming edges before removing them
    old_outgoing_targets = Map.get(outgoing_edges, vertex, %{})
    old_incoming_sources = Map.get(incoming_edges, vertex, %{})

    new_vertices = Map.delete(vertices, vertex)
    outgoing_edges_without_vertex = Map.delete(outgoing_edges, vertex)
    incoming_edges_without_vertex = Map.delete(incoming_edges, vertex)

    # Clean up edges: remove references to the removed vertex
    # from all vertices that pointed to it
    cleaned_outgoing_edges =
      Enum.reduce(old_incoming_sources, outgoing_edges_without_vertex, fn {source, _target},
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
      Enum.reduce(old_outgoing_targets, incoming_edges_without_vertex, fn {target, _source},
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
        outgoing_edges: cleaned_outgoing_edges,
        incoming_edges: cleaned_incoming_edges
    }
  end

  @doc """
  Removes multiple vertices from the graph along with all edges connected to them.
  This includes both outgoing edges from the vertices and incoming edges to the vertices.
  """
  @spec remove_vertices(t, [vertex]) :: t
  # credo:disable-for-lines:85 /Credo.Check.Refactor.ABCSize|Credo.Check.Refactor.Nesting/
  # The above Credo checks are disabled because the function is optimised this way
  def remove_vertices(graph, vertices_to_remove) do
    %Digraph2{
      vertices: vertices,
      outgoing_edges: outgoing_edges,
      incoming_edges: incoming_edges
    } = graph

    {vertices_needing_outgoing_cleanup, vertices_needing_incoming_cleanup} =
      Enum.reduce(vertices_to_remove, {MapSet.new(), MapSet.new()}, fn vertex,
                                                                       {acc_incoming_sources,
                                                                        acc_outgoing_targets} ->
        incoming_sources =
          incoming_edges
          |> Map.get(vertex, %{})
          |> Map.keys()
          |> MapSet.new()

        outgoing_targets =
          outgoing_edges
          |> Map.get(vertex, %{})
          |> Map.keys()
          |> MapSet.new()

        {MapSet.union(acc_incoming_sources, incoming_sources),
         MapSet.union(acc_outgoing_targets, outgoing_targets)}
      end)

    new_vertices = Map.drop(vertices, vertices_to_remove)
    outgoing_edges_without_removed_vertices = Map.drop(outgoing_edges, vertices_to_remove)
    incoming_edges_without_removed_vertices = Map.drop(incoming_edges, vertices_to_remove)

    # Clean up outgoing edges: remove references to removed vertices
    # from all vertices that pointed to them
    cleaned_outgoing_edges =
      Enum.reduce(
        vertices_needing_outgoing_cleanup,
        outgoing_edges_without_removed_vertices,
        fn source, acc_outgoing_edges ->
          case Map.get(acc_outgoing_edges, source) do
            nil ->
              acc_outgoing_edges

            targets ->
              cleaned_targets = Map.drop(targets, vertices_to_remove)

              if map_size(cleaned_targets) == 0 do
                Map.delete(acc_outgoing_edges, source)
              else
                Map.put(acc_outgoing_edges, source, cleaned_targets)
              end
          end
        end
      )

    # Clean up incoming edges: remove references to removed vertices
    # from all vertices they pointed to
    cleaned_incoming_edges =
      Enum.reduce(
        vertices_needing_incoming_cleanup,
        incoming_edges_without_removed_vertices,
        fn target, acc_incoming_edges ->
          case Map.get(acc_incoming_edges, target) do
            nil ->
              acc_incoming_edges

            sources ->
              cleaned_sources = Map.drop(sources, vertices_to_remove)

              if map_size(cleaned_sources) == 0 do
                Map.delete(acc_incoming_edges, target)
              else
                Map.put(acc_incoming_edges, target, cleaned_sources)
              end
          end
        end
      )

    %{
      graph
      | vertices: new_vertices,
        outgoing_edges: cleaned_outgoing_edges,
        incoming_edges: cleaned_incoming_edges
    }
  end
end
