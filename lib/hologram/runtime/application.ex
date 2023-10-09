defmodule Hologram.Runtime.Application do
  use Application

  @impl Application
  def start(_type, _args) do
    children = [
      Hologram.Router.PageModuleResover,
      Hologram.Runtime.AssetPathRegistry,
      Hologram.Runtime.AssetManifestCache,
      Hologram.Runtime.PageDigestRegistry
    ]

    opts = [strategy: :one_for_one, name: Hologram.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
