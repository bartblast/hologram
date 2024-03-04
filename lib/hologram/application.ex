defmodule Hologram.Application do
  use Application

  @impl Application
  def start(_type, _args) do
    children = [
      Hologram.Router.PageModuleResolver,
      Hologram.Assets.PathRegistry,
      Hologram.Assets.ManifestCache,
      Hologram.Assets.PageDigestRegistry
    ]

    opts = [strategy: :one_for_one, name: Hologram.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
