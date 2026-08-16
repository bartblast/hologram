defmodule Hologram.Sync.PageWindows do
  @moduledoc false

  # Which windows each page downloads, as the compiler worked them out. A connecting client names
  # the page it is on and this is what turns that into the set of windows kept for it.
  #
  # Read from a build artifact rather than worked out here: a page's windows are those of every
  # component it can REACH, which takes the call graph, and the call graph does not exist at
  # runtime. Reaching rather than rendering is the point - a panel that opens on a click has its
  # rows already there.

  use GenServer

  alias Hologram.Commons.PLT
  alias Hologram.Reflection

  @doc """
  Returns the path of the dump file the page windows are read from.
  """
  @callback dump_path() :: String.t()

  @doc """
  Returns the name of the ETS table the page windows are held in.
  """
  @callback ets_table_name() :: atom

  @doc """
  Returns the implementation of the dump file path.
  """
  @spec dump_path() :: String.t()
  def dump_path do
    Path.join([Reflection.build_dir(), Reflection.page_windows_plt_dump_file_name()])
  end

  @doc """
  Returns the implementation of the ETS table name.
  """
  @spec ets_table_name() :: atom
  def ets_table_name do
    __MODULE__
  end

  @doc """
  Returns the ids of the windows the given page downloads.

  A module that is not a page of this build has no windows rather than an error: what a client
  names is its own claim, and one naming something unknown is told about nothing rather than
  refused.
  """
  @spec lookup(module) :: list(String.t())
  def lookup(page_module) do
    windows =
      impl().ets_table_name()
      |> plt()
      |> PLT.get(page_module)

    case windows do
      {:ok, window_ids} -> window_ids
      :error -> []
    end
  end

  @doc """
  Reloads the page windows from the dump file - the live-reload path after a code change.
  """
  @spec reload() :: PLT.t()
  def reload do
    impl().ets_table_name()
    |> plt()
    |> PLT.reset()
    |> populate()
  end

  @doc """
  Starts the page windows registry.
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
    Application.get_env(:hologram, :page_windows_impl, __MODULE__)
  end

  defp plt(table_name) do
    %PLT{table_name: table_name, table_ref: :ets.whereis(table_name)}
  end

  defp populate(plt) do
    PLT.load(plt, impl().dump_path())
  end
end
