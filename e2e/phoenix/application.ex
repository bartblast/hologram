defmodule Hologram.E2E.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: Hologram.E2E.PubSub},
      Hologram.E2E.Web.Endpoint,
      Hologram.Compiler.TemplateStore
    ]

    children =
      if Mix.env() == :dev do
        children ++ [Hologram.Runtime.Watcher]
      else
        children
      end

    opts = [strategy: :one_for_one, name: Hologram.E2E.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    Hologram.E2E.Web.Endpoint.config_change(changed, removed)
    :ok
  end
end
