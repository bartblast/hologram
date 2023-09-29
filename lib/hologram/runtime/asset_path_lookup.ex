defmodule Hologram.Runtime.AssetPathLookup do
  use GenServer

  alias Hologram.Commons.FileUtils
  alias Hologram.Commons.PLT

  @doc """
  Starts AssetDigestLookup process.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:process_name])
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

  @doc """
  Returns the asset path (that includes the digest) of the given static file located in static dir.
  """
  @spec lookup(atom, String.t()) :: String.t()
  def lookup(store_key, static_path) do
    PLT.get!(%PLT{table_name: store_key}, static_path)
  end

  defp find_assets(static_path) do
    regex = ~r/^#{Regex.escape(static_path)}(.+)\-([0-9a-f]{32})(.+)$/

    static_path
    |> FileUtils.list_files_recursively()
    |> Stream.map(&Regex.run(regex, &1))
    |> Stream.filter(& &1)
    |> Stream.map(&List.to_tuple/1)
    |> stream_reject_page_bundles()
    |> stream_build_asset_entries()
    |> Enum.to_list()
  end

  defp stream_build_asset_entries(file_infos) do
    Stream.map(file_infos, fn {_file_path, prefix, digest, suffix} ->
      {prefix <> suffix, prefix <> "-" <> digest <> suffix}
    end)
  end

  defp stream_reject_page_bundles(file_infos) do
    Stream.reject(file_infos, fn {_file_path, prefix, _digest, _suffix} ->
      prefix == "/hologram/page"
    end)
  end
end
