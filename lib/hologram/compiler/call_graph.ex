# DEFER: refactor & test

defmodule Hologram.Compiler.CallGraph do
  use Agent

  def add_edge(from_vertex, to_vertex) do
    Agent.update(__MODULE__, &Graph.add_edge(&1, from_vertex, to_vertex))
  end

  def add_vertex(vertex) do
    Agent.update(__MODULE__, &Graph.add_vertex(&1, vertex))
  end

  def edges(vertex) do
    Agent.get(__MODULE__, &Graph.edges(&1, vertex))
  end

  def get do
    Agent.get(__MODULE__, & &1)
  end

  def has_edge?(from_vertex, to_vertex) do
    callback = fn call_graph ->
      edges = Graph.edges(call_graph, from_vertex, to_vertex)
      Enum.count(edges) == 1
    end

    Agent.get(__MODULE__, callback)
  end

  def has_vertex?(vertex) do
    Agent.get(__MODULE__, &Graph.has_vertex?(&1, vertex))
  end

  def num_edges do
    Agent.get(__MODULE__, &Graph.num_edges/1)
  end

  def num_vertices do
    Agent.get(__MODULE__, &Graph.num_vertices/1)
  end

  def reachable(vertices) do
    Agent.get(__MODULE__, &Graph.reachable(&1, vertices))
  end

  def run do
    Agent.start_link(fn -> Graph.new() end, name: __MODULE__)
  end

  def stop do
    Agent.stop(__MODULE__)
  end
end
