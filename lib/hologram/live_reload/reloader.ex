defmodule Hologram.LiveReload.Reloader do
  @moduledoc false
  # Shared reloading logic for both standalone and embedded modes.

  # This module contains only the logic that is common to both modes:
  # - Hologram bundles compilation
  # - Runtime registry and cache reloading

  # Mode-specific Elixir compilation and module reloading are handled by:
  # - `Hologram.LiveReload.Standalone.Reloader` for standalone mode
  # - `Hologram.LiveReload.Embedded.Reloader` for embedded mode

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
