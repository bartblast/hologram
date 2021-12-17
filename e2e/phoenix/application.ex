defmodule Hologram.E2E.Application do
  @moduledoc false

  use Application

  alias Hologram.E2E.Web.Endpoint
  alias Hologram.Runtime.{PageDigestStore, RouterBuilder, TemplateStore, Watcher}

  @env Application.fetch_env!(:hologram, :env)

  @impl true
  def start(_type, _args) do
    Hologram.Router.reload_routes()

    children = [
      {Phoenix.PubSub, name: Hologram.E2E.PubSub},
      Endpoint,
      PageDigestStore,
      RouterBuilder,
      TemplateStore
    ]

    children =
      if @env == :dev do
        children ++ [Watcher]
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
    Endpoint.config_change(changed, removed)
    :ok
  end
end
