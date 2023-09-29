defmodule Hologram.Runtime.AssetManifestCache do
  use GenServer

  @doc """
  Starts AssetManifestCache process.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl GenServer
  def init(opts) do
    manifest = build_manifest(opts[:asset_path_lookup_process_name])
    :persistent_term.put(opts[:store_key], manifest)

    {:ok, opts}
  end

  defp build_manifest(asset_path_lookup_process_name) do
    entries_js =
      asset_path_lookup_process_name
      |> GenServer.call(:get_mapping)
      |> Enum.sort()
      |> Enum.map(fn {static_path, asset_path} ->
        ~s("#{static_path}": "#{asset_path}")
      end)
      |> Enum.join(",\n")

    """
    window.__hologramAssetManifest__ = {
    #{entries_js}
    };\
    """
  end
end
