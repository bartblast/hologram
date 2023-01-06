# TODO: implement SourceFileStore and test

defmodule Hologram.Compiler.SourceFileAggregator do
  use GenServer

  alias Hologram.Compiler.Reflection
  alias Hologram.Compiler.SourceFileStore

  def run() do
    start_link(nil)
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, nil}
  end

  def aggregate(module) do
    source_path = Reflection.source_path(module)

    unless SourceFileStore.has?(source_path) do
      Task.async(fn ->
        ir =
          source_path
          |> File.read!()
          |> Reflection.ir()

        SourceFileStore.put(source_path, ir)
      end)
    end
  end
end
