defmodule Hologram.LiveReload.Reloader do
  @moduledoc false

  alias Hologram.Assets.ManifestCache
  alias Hologram.Assets.PageDigestRegistry
  alias Hologram.Assets.PathRegistry
  alias Hologram.Router.PageModuleResolver

  @doc """
  Recompiles Hologram bundles.

  This is a simple wrapper around Mix.Tasks.Compile.Hologram.run/1.
  """
  @spec recompile_hologram(keyword) :: :ok
  def recompile_hologram(opts \\ []) do
    # credo:disable-for-next-line Credo.Check.Design.AliasUsage
    Mix.Tasks.Compile.Hologram.run(opts)
  end

  @doc """
  Reloads runtime registries and caches.

  This ensures that runtime data structures are updated with
  the latest compiled code and assets.
  """
  @spec reload_runtime :: :ok
  def reload_runtime do
    PageModuleResolver.reload()
    PathRegistry.reload()
    ManifestCache.reload()
    PageDigestRegistry.reload()
    :ok
  end
end
