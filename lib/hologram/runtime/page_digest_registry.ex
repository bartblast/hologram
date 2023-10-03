defmodule Hologram.Runtime.PageDigestRegistry do
  use GenServer

  alias Hologram.Commons.PLT
  alias Hologram.Commons.Reflection

  @default_ets_table_name __MODULE__

  @doc """
  Starts PageDigestRegistry process.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts) do
    default_dump_path =
      Path.join([Reflection.build_dir(), Reflection.page_digest_plt_dump_file_name()])

    opts =
      opts
      |> Keyword.put_new(:dump_path, default_dump_path)
      |> Keyword.put_new(:ets_table_name, @default_ets_table_name)

    GenServer.start_link(__MODULE__, opts)
  end

  @impl GenServer
  def init(opts) do
    plt =
      opts
      |> Keyword.put(:table_name, opts[:ets_table_name])
      |> PLT.start()
      |> PLT.load(opts[:dump_path])

    {:ok, plt}
  end

  # TODO: maybe implement wrapper PageDigestRegistry.get_plt/1
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
  @spec lookup(module, atom) :: String.t()
  def lookup(page_module, ets_table_name \\ @default_ets_table_name) do
    PLT.get!(%PLT{table_name: ets_table_name}, page_module)
  end
end
