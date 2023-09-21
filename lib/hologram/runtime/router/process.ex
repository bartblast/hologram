defmodule Hologram.Router.Process do
  use GenServer

  alias Hologram.Commons.Reflection
  alias Hologram.Router.SearchTree

  @default_persistent_term_key {__MODULE__, :search_tree}

  @impl GenServer
  def init(persistent_term_key) do
    search_tree =
      Enum.reduce(Reflection.list_pages(), %SearchTree.Node{}, fn page, acc ->
        SearchTree.add_route(acc, page.__hologram_route__(), page)
      end)

    :persistent_term.put(persistent_term_key, search_tree)

    {:ok, nil}
  end

  @doc """
  Returns the default key for the persistent term used by the router process.
  """
  @spec default_persistent_term_key() :: {module, atom}
  def default_persistent_term_key, do: @default_persistent_term_key

  @doc """
  Given a request path it returns the page module that handles it.
  """
  @spec resolve_page(String.t(), any) :: module
  def resolve_page(request_path, persistent_term_key) do
    persistent_term_key
    |> :persistent_term.get()
    |> SearchTree.match_route(request_path)
  end
end
