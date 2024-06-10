defmodule Hologram.Router.PageModuleResolver do
  use GenServer

  alias Hologram.Commons.Reflection
  alias Hologram.Router.SearchTree

  @doc """
  Returns the key of the persistent term used by the page module resolver registered process.
  """
  @callback persistent_term_key() :: any

  @doc """
  Starts page module resolver process.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link([]) do
    GenServer.start_link(__MODULE__, nil)
  end

  @impl GenServer
  def init(nil) do
    build_search_tree_persistent_term()
    {:ok, nil}
  end

  @doc """
  Returns the implementation of the page module resolver's persistent term key.
  """
  @spec persistent_term_key() :: any
  def persistent_term_key do
    __MODULE__
  end

  def reload do
    build_search_tree_persistent_term()
  end

  @doc """
  Given a request path it returns the page module that handles it.
  """
  @spec resolve(String.t()) :: module
  def resolve(request_path) do
    impl().persistent_term_key()
    |> :persistent_term.get()
    |> SearchTree.match_route(request_path)
  end

  defp build_search_tree_persistent_term do
    search_tree =
      Enum.reduce(Reflection.list_pages(), %SearchTree.Node{}, fn page_module, acc ->
        SearchTree.add_route(acc, page_module.__route__(), page_module)
      end)

    :persistent_term.put(impl().persistent_term_key(), search_tree)
  end

  defp impl do
    Application.get_env(:hologram, :page_module_resolver_impl, __MODULE__)
  end
end
