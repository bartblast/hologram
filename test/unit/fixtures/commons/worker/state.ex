defmodule Hologram.Test.Fixtures.Commons.Worker.State do
  use Agent

  def get do
    Agent.get(__MODULE__, & &1)
  end

  def push(result) do
    Agent.update(__MODULE__, &(&1 ++ [result]))
  end

  def run do
    Agent.start_link(fn -> [] end, name: __MODULE__)
  end
end
