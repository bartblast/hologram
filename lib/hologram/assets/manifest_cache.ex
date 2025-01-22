defmodule Hologram.Assets.ManifestCache do
  @moduledoc false

  use GenServer
  alias Hologram.Assets.PathRegistry, as: AssetPathRegistry

  @doc """
  Returns the key of the persistent term used by the asset manifest cache registered process.
  """
  @callback persistent_term_key() :: any

  @doc """
  Starts asset manifest cache process.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link([]) do
    GenServer.start_link(__MODULE__, nil)
  end

  @impl GenServer
  def init(nil) do
    populate()
    {:ok, nil}
  end

  @doc """
  Returns JavaScript code that builds the asset manifest object.
  """
  @spec get_manifest_js() :: String.t()
  def get_manifest_js do
    :persistent_term.get(impl().persistent_term_key())
  end

  @doc """
  Returns the implementation of the asset manifest cache's persistent term key.
  """
  @spec persistent_term_key() :: any
  def persistent_term_key do
    __MODULE__
  end

  @doc """
  Reloads the the manifest cache data.
  """
  @spec reload :: :ok
  def reload do
    populate()
  end

  defp build_manifest do
    entries_js =
      AssetPathRegistry.get_mapping()
      |> Enum.sort()
      |> Enum.map_join(",\n", fn {static_path, asset_path} ->
        ~s("#{static_path}": "#{asset_path}")
      end)

    """
    globalThis.hologram.assetManifest = {
    #{entries_js}
    };\
    """
  end

  defp impl do
    Application.get_env(:hologram, :asset_manifest_cache_impl, __MODULE__)
  end

  defp populate do
    key = impl().persistent_term_key()
    manifest = build_manifest()
    :persistent_term.put(key, manifest)
  end
end
