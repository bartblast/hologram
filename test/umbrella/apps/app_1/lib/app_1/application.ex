defmodule App1.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: App1.PubSub},
      App1.Endpoint
    ]

    opts = [strategy: :one_for_one, name: App1.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl Application
  def config_change(changed, _new, removed) do
    App1.Endpoint.config_change(changed, removed)
    :ok
  end
end
