defmodule Hologram.Router.PageResolver do
  use GenServer

  alias Hologram.Commons.Reflection
  alias Hologram.Router.SearchTree

  @doc """
  Starts page resolver process.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts[:persistent_term_key])
  end

  @impl GenServer
  def init(persistent_term_key) do
    search_tree =
      Enum.reduce(Reflection.list_pages(), %SearchTree.Node{}, fn page, acc ->
        SearchTree.add_route(acc, page.__route__(), page)
      end)

    persistent_term_key = persistent_term_key || __MODULE__
    :persistent_term.put(persistent_term_key, search_tree)

    {:ok, nil}
  end

  @doc """
  Given a request path it returns the page module that handles it.
  """
  @spec resolve(String.t(), atom) :: module
  def resolve(request_path, persistent_term_key) do
    persistent_term_key
    |> :persistent_term.get()
    |> SearchTree.match_route(request_path)
  end
end
