defmodule Hologram.Assets.ManifestCache do
  @moduledoc false

  use GenServer
  alias Hologram.Assets.PathRegistry, as: AssetPathRegistry
  alias Hologram.Compiler.Encoder

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
  Returns the asset manifest as JSON: an object mapping each static file's path to its asset path,
  with the paths in alphabetical order.

  Built once and cached rather than encoded per request, since the mapping changes only when the
  assets do. Nothing in it is escaped for HTML, so it reaches a page only inside the boot data
  block, which escapes it (see `Hologram.Template.Renderer.interpolate_boot_data/3`).
  """
  @spec get_manifest_json() :: String.t()
  def get_manifest_json do
    :persistent_term.get(json_persistent_term_key())
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
      # Each path is printed into the inline script the manifest is part of, as a string literal,
      # so it is encoded the way every other value in that script is: a quote or a backslash would
      # break the literal, a line break would end it, and a `<` could spell the closing tag of the
      # script element around it. The names come from the static dir, not from a request - this
      # guards against a file named hostilely, not a hostile request.
      |> Enum.map_join(",\n", fn {static_path, asset_path} ->
        "#{Encoder.encode_as_string(static_path)}: #{Encoder.encode_as_string(asset_path)}"
      end)

    """
    {
    #{entries_js}
    };\
    """
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

  defp json_persistent_term_key do
    {impl().persistent_term_key(), :json}
  end

  defp populate do
    key = impl().persistent_term_key()
    manifest = build_manifest()
    :persistent_term.put(key, manifest)

    manifest_json = build_manifest_json()
    :persistent_term.put(json_persistent_term_key(), manifest_json)
  end
end
