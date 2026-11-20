defmodule Hologram.DB.QueryCache do
  @moduledoc false

  use GenServer

  alias Hologram.Commons.SerializationUtils
  alias Hologram.DB
  alias Hologram.Entity.Derived
  alias Hologram.Reflection

  @doc """
  Returns the path of the dump file the query cache is read from.
  """
  @callback dump_path() :: String.t()

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
  Returns the implementation of the path of the dump file the query cache is read from.
  """
  @spec dump_path() :: String.t()
  def dump_path do
    Path.join([Reflection.build_dir(), Reflection.queries_plt_dump_file_name()])
  end

  @doc """
  Returns true when the build has a page checking permissions on the client, or false otherwise -
  as the build decided it.

  Such a client answers each rule over the rows it holds, so it needs the rows its types' rules
  read synced too, and the server's verdicts carried on the rows.
  """
  @spec permission_checking?() :: boolean
  def permission_checking? do
    :persistent_term.get(impl().persistent_term_key()).permission_checking?
  end

  @doc """
  Returns the entity types sync sends rows of, sorted - as the build listed them (see
  `Hologram.Compiler.build_sync_constants/2`). A type left out is one no browser code reads and no
  rule a browser answers reads, save through a type no session may read, so no browser gets its
  rows.
  """
  @spec synced_types() :: list(module)
  def synced_types do
    :persistent_term.get(impl().persistent_term_key()).synced_types
  end

  @doc """
  Returns the implementation of the query cache's persistent term key.
  """
  @spec persistent_term_key() :: any
  def persistent_term_key do
    __MODULE__
  end

  @doc """
  Re-reads the query cache from the compiler's dump - the live-reload path after
  a dev code change, where the recompile that precedes it has rewritten the dump.
  A no-op when the database is not running (no entities declared at boot).
  Returns :ok.
  """
  @spec reload() :: :ok
  def reload do
    if Process.whereis(DB) do
      populate()
    end

    :ok
  end

  defp impl do
    Application.get_env(:hologram, :query_cache_impl, __MODULE__)
  end

  # Read rather than rebuilt: the build already worked all of this out from the call graph, which a
  # release does not ship, so a boot could not repeat the work.
  defp populate do
    data =
      impl().dump_path()
      |> File.read!()
      |> SerializationUtils.deserialize(true)

    # The build resolved every derived field's definition, so the runtime reads them from the dump
    # rather than resolving them again - a definition calling a query builder is resolved by walking
    # the builder's IR, which a release does not ship.
    Derived.put_definitions(data.derived)

    :persistent_term.put(impl().persistent_term_key(), data)
  end
end
