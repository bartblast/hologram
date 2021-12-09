# DEFER: refactor & test

defmodule Hologram.Compiler.CallGraph do
  use Agent

  def add_edge(from_vertex, to_vertex) do
    Agent.update(__MODULE__, &(&1.add_edge(from_vertex, to_vertex)))
  end

  def add_vertex(vertex) do
    Agent.update(__MODULE__, &(&1.add_vertex(vertex)))
  end

  def create do
    start_link(nil)
  end

  def destroy do
    Process.whereis(__MODULE__) |> Process.exit(:normal)
  end

  def has_vertex?(vertex) do
    Agent.get(__MODULE__, &(&1.has_vertex?(vertex)))
  end

  def start_link(_) do
    Agent.start_link(fn -> Graph.new() end, name: __MODULE__)
  end
end
