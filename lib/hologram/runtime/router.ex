defmodule Hologram.Router do
  use GenServer

  alias Hologram.Compiler.Reflection
  alias Hologram.Router.SearchTree

  def start_link(name \\ __MODULE__) do
    GenServer.start_link(__MODULE__, name, name: name)
  end

  def init(name) do
    search_tree =
      Enum.reduce(Reflection.list_pages(), %SearchTree.Node{}, fn page, acc ->
        SearchTree.add_route(acc, page.__hologram_route__(), page)
      end)

    :ets.new(name, [:named_table, :public, {:read_concurrency, true}])
    :ets.insert(name, {:search_tree, search_tree})

    {:ok, nil}
  end
end
