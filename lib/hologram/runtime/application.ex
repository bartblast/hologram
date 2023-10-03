defmodule Hologram.Runtime.Application do
  use Application

  alias Hologram.Router.PageResolver
  alias Hologram.Runtime.AssetManifestCache
  alias Hologram.Runtime.AssetPathRegistry
  alias Hologram.Runtime.PageDigestRegistry

  @impl Application
  def start(_type, _args) do
    children = [
      AssetPathRegistry,
      {AssetManifestCache,
       asset_path_registry_process_name: AssetPathRegistry, store_key: AssetManifestCache},
      PageDigestRegistry,
      PageResolver
    ]

    opts = [strategy: :one_for_one, name: Hologram.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
