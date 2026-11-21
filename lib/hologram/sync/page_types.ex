defmodule Hologram.Sync.PageTypes do
  @moduledoc false

  # Which synced types a session on each page fills first, as the compiler worked them out: those
  # the page's own code reads, with the ones its rules read when it checks permissions. A connecting
  # client names the page it is on, and its session fills these types first: what a client keeps is
  # app-wide, every synced type, and the page only decides what arrives first, so the page the
  # client opened is answered before the rest.
  #
  # Read from a build artifact rather than worked out here: a page's types are those of every
  # function and component it can REACH, which takes the call graph, and the call graph does not
  # exist at runtime. Reaching rather than rendering is the point - a panel that opens on a click
  # has its rows already there.

  use GenServer

  alias Hologram.Commons.PLT
  alias Hologram.Commons.SerializationUtils
  alias Hologram.Reflection

  @doc """
  Returns the path of the dump file the page types are read from.
  """
  @callback dump_path() :: String.t()

  @doc """
  Returns the name of the ETS table the page types are held in.
  """
  @callback ets_table_name() :: atom

  @doc """
  Returns the implementation of the dump file path.
  """
  @spec dump_path() :: String.t()
  def dump_path do
    Path.join([Reflection.build_dir(), Reflection.page_types_plt_dump_file_name()])
  end

  @doc """
  Returns the implementation of the ETS table name.
  """
  @spec ets_table_name() :: atom
  def ets_table_name do
    __MODULE__
  end

  @doc """
  Returns the synced types a session on the given page fills first, sorted by name.

  A module that is not a page of this build has no types rather than an error: what a client names
  is its own claim, and one naming something unknown is filled in the build's order rather than
  refused.
  """
  @spec lookup(module) :: list(module)
  def lookup(page_module) do
    types =
      impl().ets_table_name()
      |> plt()
      |> PLT.get(page_module)

    case types do
      {:ok, entity_types} -> entity_types
      :error -> []
    end
  end

  @doc """
  Reloads the page types from the dump file - the live-reload path after a code change.

  The replacement is read before anything published changes, and applied over what is there: a
  clearing followed by a filling would answer "no types" for a page that has them, to anyone
  looking in between, and a session starting on that answer would fill its page's rows in no
  particular place.
  """
  @spec reload() :: PLT.t()
  def reload do
    plt = plt(impl().ets_table_name())
    fresh = read_dump()

    PLT.put(plt, Map.to_list(fresh))

    # What the build no longer has, removed after the rest is in place rather than before it. A
    # page removed here is one no client can name any more.
    plt
    |> PLT.get_all()
    |> Map.keys()
    |> Enum.reject(&Map.has_key?(fresh, &1))
    |> Enum.each(&PLT.delete(plt, &1))

    plt
  end

  @doc """
  Starts the page types registry.
  """
  @spec start_link([]) :: GenServer.on_start()
  def start_link([]) do
    GenServer.start_link(__MODULE__, nil)
  end

  @impl GenServer
  def init(nil) do
    [table_name: impl().ets_table_name()]
    |> PLT.start()
    |> populate()

    {:ok, nil}
  end

  defp impl do
    Application.get_env(:hologram, :sync_page_types_impl, __MODULE__)
  end

  defp plt(table_name) do
    %PLT{table_name: table_name, table_ref: :ets.whereis(table_name)}
  end

  defp populate(plt) do
    PLT.load(plt, impl().dump_path())
  end

  defp read_dump do
    impl().dump_path()
    |> File.read!()
    |> SerializationUtils.deserialize(true)
  end
end
