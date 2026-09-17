defmodule Hologram.Router.PageModuleResolver do
  @moduledoc false

  use GenServer

  alias Hologram.Commons.PLT
  alias Hologram.Reflection
  alias Hologram.Router.SearchTree

  @doc """
  Returns the path of the dump file the page module resolver reads the pages and their routes from.
  """
  @callback dump_path() :: String.t()

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
    populate_persistent_term()
    {:ok, nil}
  end

  @doc """
  Returns the implementation of the page module resolver's dump path: the module info PLT dump the
  compiler writes at the end of every compile, which records every page and its route.
  """
  @spec dump_path() :: String.t()
  def dump_path do
    Path.join([Reflection.build_dir(), Reflection.module_info_plt_dump_file_name()])
  end

  @doc """
  Returns the implementation of the page module resolver's persistent term key.
  """
  @spec persistent_term_key() :: any
  def persistent_term_key do
    __MODULE__
  end

  @doc """
  Reloads the persistent term that stores the search tree used for page module resolving.
  """
  @spec reload :: :ok
  def reload do
    populate_persistent_term()
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

  # The pages and their routes come from the compiler's dump, so no module is asked whether it is a
  # page, which would read the BEAM of every module that is not loaded, at boot and on every reload.
  # Each routed page is loaded, as the route calls this replaces did: requests turn names from the
  # browser into existing atoms only, and a page's names exist once its module is loaded. A page
  # whose module cannot be loaded (its BEAM gone since the dump) is not routed.
  defp build_search_tree do
    plt = PLT.start()

    try do
      plt
      |> PLT.load(impl().dump_path())
      |> PLT.get_all()
      |> Enum.reduce(%SearchTree.Node{}, fn
        {page_module, %{page?: true, route: route}}, acc when is_binary(route) ->
          if Code.ensure_loaded?(page_module) do
            SearchTree.add_route(acc, route, page_module)
          else
            acc
          end

        _other, acc ->
          acc
      end)
    after
      PLT.stop(plt)
    end
  end

  defp impl do
    Application.get_env(:hologram, :page_module_resolver_impl, __MODULE__)
  end

  defp populate_persistent_term do
    search_tree = build_search_tree()
    persistent_term_key = impl().persistent_term_key()

    :persistent_term.put(persistent_term_key, search_tree)
  end
end
