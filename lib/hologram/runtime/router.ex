defmodule Hologram.Router do
  use GenServer

  alias Hologram.Compiler.Reflection
  alias Hologram.Router.SearchTree

  @impl GenServer
  def init(name) do
    search_tree =
      Enum.reduce(Reflection.list_pages(), %SearchTree.Node{}, fn page, acc ->
        SearchTree.add_route(acc, page.__hologram_route__(), page)
      end)

    :persistent_term.put({name, :search_tree}, search_tree)

    {:ok, nil}
  end
end
