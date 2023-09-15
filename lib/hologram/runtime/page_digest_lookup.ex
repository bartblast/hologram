defmodule Hologram.Runtime.PageDigestLookup do
  use GenServer
  alias Hologram.Commons.PLT

  @impl GenServer
  def init(opts) do
    plt =
      opts
      |> PLT.start()
      |> PLT.load(opts[:dump_path])

    {:ok, plt}
  end
end
