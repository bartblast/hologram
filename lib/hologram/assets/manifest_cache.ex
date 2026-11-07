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
  Returns the process name registered for the asset manifest cache.
  """
  @callback process_name() :: atom

  @doc """
  Starts asset manifest cache process.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link([]) do
    GenServer.start_link(__MODULE__, nil, name: impl().process_name())
  end

  @impl GenServer
  def init(nil) do
    populate()
    {:ok, nil}
  end

  @doc """
  Rebuilds the manifest.
  """
  @impl GenServer
  @spec handle_call(:reload, GenServer.from(), nil) :: {:reply, :ok, nil}
  def handle_call(:reload, _from, nil) do
    populate()
    {:reply, :ok, nil}
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
  Returns the implementation of the asset manifest cache's process name.
  """
  @spec process_name() :: atom
  def process_name do
    __MODULE__
  end

  @doc """
  Rebuilds the manifest from the asset path registry. The rebuilds run one at a time in the cache's
  process, each reading the registry as it is then, so the manifest ends up built from the registry
  as the last change before the last rebuild left it.
  """
  @spec reload :: :ok
  def reload do
    GenServer.call(impl().process_name(), :reload)
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

  defp impl do
    Application.get_env(:hologram, :asset_manifest_cache_impl, __MODULE__)
  end

  defp populate do
    key = impl().persistent_term_key()
    manifest = build_manifest()
    :persistent_term.put(key, manifest)
  end
end
