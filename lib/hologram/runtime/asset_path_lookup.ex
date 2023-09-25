defmodule Hologram.Runtime.AssetPathLookup do
  use GenServer

  alias Hologram.Commons.FileUtils
  alias Hologram.Commons.PLT

  @doc """
  Starts AssetDigestLookup process.
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

    opts[:static_path]
    |> find_assets()
    |> Enum.each(fn {key, value} -> PLT.put(plt, key, value) end)

    {:ok, plt}
  end

  defp find_assets(static_path) do
    regex = ~r/^#{Regex.escape(static_path)}(.+)\-([0-9a-f]{32})(.+)$/

    static_path
    |> FileUtils.list_files_recursively()
    |> Stream.map(&Regex.run(regex, &1))
    |> Stream.filter(& &1)
    |> Stream.map(&List.to_tuple/1)
    |> Stream.reject(fn {_, prefix, _, _} -> prefix == "/hologram/page" end)
    |> Stream.map(fn {_, prefix, digest, suffix} ->
      {prefix <> suffix, prefix <> "-" <> digest <> suffix}
    end)
    |> Enum.to_list()
  end
end
