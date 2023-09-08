defmodule Hologram.Router do
  use GenServer

  alias Hologram.Compiler.Reflection
  alias Hologram.Router.SearchTree

  @persistent_term_key {__MODULE__, :search_tree}

  @impl GenServer
  def init(persistent_term_key \\ @persistent_term_key) do
    search_tree =
      Enum.reduce(Reflection.list_pages(), %SearchTree.Node{}, fn page, acc ->
        SearchTree.add_route(acc, page.__hologram_route__(), page)
      end)

    :persistent_term.put(persistent_term_key, search_tree)

    {:ok, nil}
  end

  @doc """
  Given a URL path returns the page module that handles it.
  """

  @spec resolve_page(String.t(), any) :: module
  def resolve_page(url_path, persistent_term_key \\ @persistent_term_key) do
    persistent_term_key
    |> :persistent_term.get()
    |> SearchTree.match_route(url_path)
  end
end
