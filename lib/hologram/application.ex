defmodule Hologram.Application do
  use Application

  @env Application.compile_env!(:hologram, :env)

  def env, do: @env

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
