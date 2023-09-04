defmodule Hologram.Router do
  use GenServer

  alias Hologram.Compiler.Reflection
  alias Hologram.Router.SearchTree

  @impl GenServer
  def init(persistent_term_name \\ {__MODULE__, :search_tree}) do
    search_tree =
      Enum.reduce(Reflection.list_pages(), %SearchTree.Node{}, fn page, acc ->
        SearchTree.add_route(acc, page.__hologram_route__(), page)
      end)

    :persistent_term.put(persistent_term_name, search_tree)

    {:ok, nil}
  end
end
