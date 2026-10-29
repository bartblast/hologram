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
  Returns the asset manifest as JSON: an object mapping each static file's path to its asset path,
  with the paths in alphabetical order.

  Built once and cached rather than encoded per request, since the mapping changes only when the
  assets do. Nothing in it is escaped for HTML, so it reaches a page only inside the boot data
  block, which escapes it (see `Hologram.Template.Renderer.boot_data_element/2`).
  """
  @spec get_manifest_json() :: String.t()
  def get_manifest_json do
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

  defp build_manifest_json do
    AssetPathRegistry.get_mapping()
    |> Enum.sort()
    |> Jason.OrderedObject.new()
    |> Jason.encode!()
  end

  defp impl do
    Application.get_env(:hologram, :asset_manifest_cache_impl, __MODULE__)
  end

  defp populate do
    key = impl().persistent_term_key()
    manifest_json = build_manifest_json()
    :persistent_term.put(key, manifest_json)
  end
end
