defmodule Hologram.Assets.PageDigestRegistry do
  @moduledoc false

  use GenServer

  alias Hologram.Commons.PLT
  alias Hologram.Reflection

  @doc """
  Returns the path of the dump file used by the page digest registry registered process.
  """
  @callback dump_path() :: String.t()

  @doc """
  Returns the name of the ETS table used by the page digest registry registered process.
  """
  @callback ets_table_name() :: atom

  @doc """
  Starts page digest registry process.
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

  @doc """
  Returns the digest of the given page module.
  """
  @spec lookup(module) :: String.t()
  def lookup(page_module) do
    impl().ets_table_name()
    |> plt()
    |> PLT.get!(page_module)
  end

  @doc """
  Returns the implementation of the page digest registry's dump path.
  """
  @spec dump_path() :: String.t()
  def dump_path do
    Path.join([Reflection.build_dir(), Reflection.page_digest_plt_dump_file_name()])
  end

  @doc """
  Returns the implementation of the page digest registry's ETS table name.
  """
  @spec ets_table_name() :: atom
  def ets_table_name do
    __MODULE__
  end

  @doc """
  Reloads the page digest registry data.
  """
  @spec reload :: PLT.t()
  def reload do
    impl().ets_table_name()
    |> plt()
    |> PLT.reset()
    |> populate()
  end

  defp impl do
    Application.get_env(:hologram, :page_digest_registry_impl, __MODULE__)
  end

  defp plt(table_name) do
    %PLT{table_name: table_name, table_ref: :ets.whereis(table_name)}
  end

  defp populate(plt) do
    PLT.load(plt, impl().dump_path())
  end
end
