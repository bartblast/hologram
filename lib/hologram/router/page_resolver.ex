defmodule Hologram.Router.PageResolver do
  use GenServer

  alias Hologram.Commons.Reflection
  alias Hologram.Router.SearchTree

  @doc """
  Starts page resolver process.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts[:store_key])
  end

  @impl GenServer
  def init(store_key) do
    search_tree =
      Enum.reduce(Reflection.list_pages(), %SearchTree.Node{}, fn page, acc ->
        SearchTree.add_route(acc, page.__hologram_route__(), page)
      end)

    :persistent_term.put(store_key, search_tree)

    {:ok, nil}
  end

  @doc """
  Given a request path it returns the page module that handles it.
  """
  @spec resolve(String.t(), atom) :: module
  def resolve(request_path, store_key) do
    store_key
    |> :persistent_term.get()
    |> SearchTree.match_route(request_path)
  end
end
