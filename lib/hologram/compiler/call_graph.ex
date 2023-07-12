defmodule Hologram.Compiler.CallGraph do
  use Agent
  alias Hologram.Compiler.CallGraph

  defstruct pid: nil, name: nil
  @type t :: %CallGraph{pid: pid, name: atom}

  def add_edge(call_graph, from_vertex, to_vertex) do
    Agent.update(call_graph.name, &Graph.add_edge(&1, from_vertex, to_vertex))
  end

  def add_vertex(call_graph, vertex) do
    Agent.update(call_graph.name, &Graph.add_vertex(&1, vertex))
  end

  def data(call_graph) do
    Agent.get(call_graph, & &1)
  end

  def edges(call_graph, vertex) do
    Agent.get(call_graph.name, &Graph.edges(&1, vertex))
  end

  def has_edge?(call_graph, from_vertex, to_vertex) do
    getter = fn graph ->
      edges = Graph.edges(graph, from_vertex, to_vertex)
      Enum.count(edges) == 1
    end

    Agent.get(call_graph.name, getter)
  end

  def has_vertex?(call_graph, vertex) do
    Agent.get(call_graph, &Graph.has_vertex?(&1, vertex))
  end

  def num_edges(call_graph) do
    Agent.get(call_graph, &Graph.num_edges/1)
  end

  def num_vertices(call_graph) do
    Agent.get(call_graph, &Graph.num_vertices/1)
  end

  def reachable(call_graph, vertices) do
    Agent.get(call_graph, &Graph.reachable(&1, vertices))
  end

  @doc """
  Starts a new CallGraph agent with an initial empty graph.

  ## Examples

      iex> start(name: :my_call_graph)
      %Hologram.Compiler.CallGraph{
        pid: #PID<0.259.0>,
        name: :my_call_graph
      }
  """
  @spec start(keyword) :: CallGraph.t()
  def start(opts) do
    {:ok, pid} = Agent.start_link(fn -> Graph.new() end, name: opts[:name])
    %CallGraph{pid: pid, name: opts[:name]}
  end

  def stop(call_graph) do
    Agent.stop(call_graph.name)
  end
end
