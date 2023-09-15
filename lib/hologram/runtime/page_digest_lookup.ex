defmodule Hologram.Runtime.PageDigestLookup do
  use GenServer
  alias Hologram.Commons.PLT

  @impl GenServer
  def init(opts) do
    plt =
      opts
      |> Keyword.put(:table_name, opts[:table_name] || __MODULE__)
      |> PLT.start()
      |> PLT.load(opts[:dump_path])

    {:ok, plt}
  end

  @doc """
  Returns the digest of the given page module.
  """
  @spec lookup(atom, module) :: String.t()
  def lookup(table_name, page_module) do
    PLT.get!(%PLT{table_name: table_name}, page_module)
  end
end
