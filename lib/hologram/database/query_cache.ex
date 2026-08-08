defmodule Hologram.Database.QueryCache do
  @moduledoc false

  use GenServer

  alias Hologram.Compiler.QueryExtractor
  alias Hologram.Database
  alias Hologram.Database.QueryCompiler
  alias Hologram.Query.Registry
  alias Hologram.Reflection

  @doc """
  Returns the modules swept for registered queries.
  """
  @callback component_modules() :: list(module)

  @doc """
  Returns the key of the persistent term used by the query cache registered process.
  """
  @callback persistent_term_key() :: any

  @doc """
  Starts query cache process.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link([]) do
    GenServer.start_link(__MODULE__, nil)
  end

  @impl GenServer
  def init(nil) do
    populate()
    {:ok, nil}
  end

  @doc """
  Returns the modules swept for registered queries - all component modules in the project.
  """
  @spec component_modules() :: list(module)
  def component_modules do
    Reflection.list_components()
  end

  @doc """
  Returns all query cache entries - a map from query content ID to the registry
  entry extended with the query's compiled form under the :compiled key.
  """
  @spec entries() :: %{String.t() => %{atom => any}}
  def entries do
    :persistent_term.get(impl().persistent_term_key()).entries
  end

  @doc """
  Returns {:ok, entry} for the given query content ID, or :error when no query
  with the given ID is registered.
  """
  @spec fetch(String.t()) :: {:ok, %{atom => any}} | :error
  def fetch(id) do
    Map.fetch(entries(), id)
  end

  @doc """
  Returns the implementation of the query cache's persistent term key.
  """
  @spec persistent_term_key() :: any
  def persistent_term_key do
    __MODULE__
  end

  @doc """
  Returns the ordered argument names of the parameterized from_query capture
  declared for the given component prop, or nil when the prop declares none.
  """
  @spec prop_params(module, atom) :: list(atom | nil) | nil
  def prop_params(module, prop_name) do
    key = impl().persistent_term_key()

    Map.get(:persistent_term.get(key).prop_params, {module, prop_name})
  end

  @doc """
  Rebuilds the query cache from the current component modules and mapping - the
  live-reload path after a dev code change. A no-op when the database is not
  running (no entities declared at boot). Returns :ok.
  """
  @spec reload() :: :ok
  def reload do
    if Process.whereis(Database) do
      populate()
    end

    :ok
  end

  defp impl do
    Application.get_env(:hologram, :query_cache_impl, __MODULE__)
  end

  defp populate do
    mapping = Database.mapping()
    modules = impl().component_modules()

    entries =
      modules
      |> QueryExtractor.extract_queries()
      |> Registry.build()
      |> Map.new(fn {id, entry} ->
        {id, Map.put(entry, :compiled, QueryCompiler.compile(entry.term, mapping))}
      end)

    prop_params =
      modules
      |> Enum.flat_map(fn module ->
        module
        |> QueryExtractor.extract_prop_params()
        |> Enum.map(fn {prop_name, param_names} -> {{module, prop_name}, param_names} end)
      end)
      |> Map.new()

    data = %{entries: entries, prop_params: prop_params}

    :persistent_term.put(impl().persistent_term_key(), data)
  end
end
