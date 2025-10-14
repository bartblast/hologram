defmodule Hologram.Compiler.Digraph do
  @moduledoc false

  alias Hologram.Compiler.Digraph

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
    %Digraph{
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

    %Digraph{
      vertices: new_vertices,
      outgoing_edges: new_outgoing_edges,
      incoming_edges: new_incoming_edges
    }
  end

  @doc """
  Adds multiple edges to the graph.
  Automatically adds vertices if they don't exist.
  """
  @spec add_edges(t, [edge]) :: t
  # credo:disable-for-lines:41 Credo.Check.Refactor.ABCSize
  # The above Credo check is disabled because the function is optimised this way
  def add_edges(graph, added_edges) do
    %Digraph{
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

    %Digraph{
      vertices: new_vertices,
      outgoing_edges: new_outgoing_edges,
      incoming_edges: new_incoming_edges
    }
  end

  @doc """
  Adds a vertex to the graph.
  """
  @spec add_vertex(t, vertex) :: t
  def add_vertex(%Digraph{vertices: vertices} = graph, vertex) do
    %{graph | vertices: Map.put(vertices, vertex, true)}
  end

  @doc """
  Adds multiple vertices to the graph.
  """
  @spec add_vertices(t, [vertex]) :: t
  def add_vertices(%Digraph{vertices: old_vertices} = graph, added_vertices) do
    new_vertices =
      Enum.reduce(added_vertices, old_vertices, fn vertex, acc ->
        Map.put(acc, vertex, true)
      end)

    %{graph | vertices: new_vertices}
  end

  @doc """
  Returns a list of all edges in the graph.
  Each edge is represented as a tuple {source_vertex, target_vertex}.
  """
  @spec edges(t) :: [edge]
  def edges(graph) do
    %Digraph{outgoing_edges: outgoing_edges} = graph

    for {source, targets} <- outgoing_edges, {target, _flag} <- targets do
      {source, target}
    end
  end

  @doc """
  Checks if an edge exists between source and target.
  """
  @spec has_edge?(t, vertex, vertex) :: boolean
  def has_edge?(graph, source, target) do
    %Digraph{outgoing_edges: outgoing_edges} = graph

    case Map.get(outgoing_edges, source) do
      nil -> false
      targets -> Map.has_key?(targets, target)
    end
  end

  @doc """
  Checks if a vertex exists in the graph.
  """
  @spec has_vertex?(t, vertex) :: boolean
  def has_vertex?(graph, vertex) do
    %Digraph{vertices: vertices} = graph
    Map.has_key?(vertices, vertex)
  end

  @doc """
  Returns a list of all incoming edges to the given vertex.
  Each edge is represented as a tuple {source_vertex, target_vertex}.
  """
  @spec incoming_edges(t, vertex) :: [edge]
  def incoming_edges(%Digraph{incoming_edges: incoming_edges_map}, vertex) do
    incoming_edges_map
    |> Map.get(vertex, %{})
    |> Enum.map(fn {source, _flag} -> {source, vertex} end)
  end

  @doc """
  Creates a new directed graph.
  """
  @spec new :: t
  def new do
    %Digraph{vertices: %{}, outgoing_edges: %{}, incoming_edges: %{}}
  end

  @doc """
  Returns a list of all vertices reachable from the given list of starting vertices.
  Uses breadth-first search to efficiently traverse the graph.
  If none of the starting vertices exist in the graph, returns an empty list.
  Non-existent starting vertices are ignored.
  """
  @spec reachable(t, [vertex]) :: [vertex]
  def reachable(graph, starting_vertices) do
    %Digraph{vertices: vertices, outgoing_edges: outgoing_edges} = graph

    existing_vertices = Enum.filter(starting_vertices, &Map.has_key?(vertices, &1))

    if existing_vertices == [] do
      []
    else
      # BFS to find all reachable vertices
      queue = :queue.from_list(existing_vertices)
      visited = MapSet.new(existing_vertices)

      queue
      |> bfs_reachable(visited, outgoing_edges)
      |> MapSet.to_list()
    end
  end

  @doc """
  Removes a vertex from the graph along with all edges connected to it.
  This includes both outgoing edges from the vertex and incoming edges to the vertex.
  """
  @spec remove_vertex(t, vertex) :: t
  # credo:disable-for-lines:63 /Credo.Check.Refactor.ABCSize|Credo.Check.Refactor.Nesting/
  # The above Credo checks are disabled because the function is optimised this way
  def remove_vertex(graph, vertex) do
    %Digraph{
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
    %Digraph{
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

  @doc """
  Returns the shortest path from source to target vertex as a list of vertices.
  Returns nil if no path exists or if either vertex is not in the graph.
  If source equals target, returns a single-element list [source].
  """
  @spec shortest_path(t, vertex, vertex) :: [vertex] | nil
  def shortest_path(graph, source, target) do
    %Digraph{vertices: vertices, outgoing_edges: outgoing_edges} = graph

    cond do
      not (Map.has_key?(vertices, source) and Map.has_key?(vertices, target)) ->
        nil

      source == target ->
        [source]

      true ->
        queue = :queue.from_list([source])
        visited = MapSet.new([source])
        parents = %{}

        case bfs_shortest_path(queue, visited, parents, target, outgoing_edges) do
          nil -> nil
          parents_map -> reconstruct_path(parents_map, source, target)
        end
    end
  end

  @doc """
  Returns all edges in the graph sorted in ascending order.
  """
  @spec sorted_edges(t) :: [edge]
  def sorted_edges(graph) do
    graph
    |> edges()
    |> Enum.sort()
  end

  @doc """
  Returns all vertices in the graph sorted in ascending order.
  """
  @spec sorted_vertices(t) :: [vertex]
  def sorted_vertices(graph) do
    graph
    |> vertices()
    |> Enum.sort()
  end

  @doc """
  Returns a list of all vertices in the graph.
  """
  @spec vertices(t) :: [vertex]
  def vertices(%Digraph{vertices: vertices}) do
    Map.keys(vertices)
  end

  # BFS traversal for reachable vertices
  # credo:disable-for-lines:27 Credo.Check.Refactor.Nesting
  # The above Credo check is disabled because the function is optimised this way
  defp bfs_reachable(queue, visited, outgoing_edges) do
    case :queue.out(queue) do
      {{:value, current}, rest_queue} ->
        # Get neighbors of current vertex
        neighbors = Map.get(outgoing_edges, current, %{})

        # Add unvisited neighbors to queue and visited set
        {new_queue, new_visited} =
          Enum.reduce(neighbors, {rest_queue, visited}, fn {neighbor, _flag},
                                                           {acc_queue, acc_visited} ->
            if MapSet.member?(acc_visited, neighbor) do
              {acc_queue, acc_visited}
            else
              {
                :queue.in(neighbor, acc_queue),
                MapSet.put(acc_visited, neighbor)
              }
            end
          end)

        bfs_reachable(new_queue, new_visited, outgoing_edges)

      {:empty, _queue} ->
        visited
    end
  end

  # BFS traversal for shortest path using parent tracking
  defp bfs_shortest_path(queue, visited, parents, target, outgoing_edges) do
    case :queue.out(queue) do
      {{:value, current}, rest_queue} ->
        neighbors = Map.get(outgoing_edges, current, %{})

        case process_neighbors(neighbors, current, target, rest_queue, visited, parents) do
          {:found, final_parents} ->
            final_parents

          {new_queue, new_visited, new_parents} ->
            bfs_shortest_path(new_queue, new_visited, new_parents, target, outgoing_edges)
        end

      {:empty, _queue} ->
        nil
    end
  end

  # Process neighbors during BFS traversal
  defp process_neighbors(neighbors, current, target, queue, visited, parents) do
    Enum.reduce_while(neighbors, {queue, visited, parents}, fn {neighbor, _flag},
                                                               {acc_queue, acc_visited,
                                                                acc_parents} ->
      cond do
        neighbor == target ->
          {:halt, {:found, Map.put(acc_parents, target, current)}}

        MapSet.member?(acc_visited, neighbor) ->
          {:cont, {acc_queue, acc_visited, acc_parents}}

        true ->
          {:cont,
           {
             :queue.in(neighbor, acc_queue),
             MapSet.put(acc_visited, neighbor),
             Map.put(acc_parents, neighbor, current)
           }}
      end
    end)
  end

  # Reconstruct path from parent map
  defp reconstruct_path(parents, source, target) do
    reconstruct_path(parents, source, target, [target])
  end

  defp reconstruct_path(_parents, source, current, path) when current == source do
    path
  end

  defp reconstruct_path(parents, source, current, path) do
    parent = Map.fetch!(parents, current)
    reconstruct_path(parents, source, parent, [parent | path])
  end
end
