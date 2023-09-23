defmodule Hologram.Runtime.PageDigestLookup do
  use GenServer
  alias Hologram.Commons.PLT

  @doc """
  Starts PageDigestLookup process.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl GenServer
  def init(opts) do
    plt =
      opts
      |> Keyword.put(:table_name, opts[:store_key])
      |> PLT.start()
      |> PLT.load(opts[:dump_path])

    {:ok, plt}
  end

  @doc """
  Returns the underlying PLT.
  """
  @impl GenServer
  @spec handle_call(:get_plt, GenServer.from(), PLT.t()) :: {:reply, PLT.t(), PLT.t()}
  def handle_call(:get_plt, _from, plt) do
    {:reply, plt, plt}
  end

  @doc """
  Returns the digest of the given page module.
  """
  @spec lookup(atom, module) :: String.t()
  def lookup(store_key, page_module) do
    PLT.get!(%PLT{table_name: store_key}, page_module)
  end
end
