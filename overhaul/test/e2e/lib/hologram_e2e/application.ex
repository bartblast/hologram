defmodule HologramE2E.Application do
  use Application
  alias HologramE2EWeb.Endpoint

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: HologramE2E.PubSub},
      Endpoint
    ]

    opts = [strategy: :one_for_one, name: HologramE2E.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    Endpoint.config_change(changed, removed)
    :ok
  end
end
