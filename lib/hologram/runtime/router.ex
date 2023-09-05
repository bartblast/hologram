defmodule Hologram.Router do
  use GenServer

  alias Hologram.Compiler.Reflection
  alias Hologram.Router.SearchTree

  @persistent_term_key {__MODULE__, :search_tree}

  @doc """
  Extracts param values from the given URL path corresponding to the route of the given page module.
  """
  @spec extract_params(String.t(), module) :: %{atom => any}
  def extract_params(url_path, page) do
    route_segments = String.split(page.__hologram_route__(), "/")
    url_path_segments = String.split(url_path, "/")

    route_segments
    |> Enum.zip(url_path_segments)
    |> Enum.reduce([], fn
      {":" <> key, value}, acc ->
        [{String.to_existing_atom(key), value} | acc]

      _non_param_segment, acc ->
        acc
    end)
    |> Enum.into(%{})
  end

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
