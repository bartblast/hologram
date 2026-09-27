defmodule HologramEcosystemTests.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: HologramEcosystemTests.PubSub},
      HologramEcosystemTestsWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: HologramEcosystemTests.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl Application
  def config_change(changed, _new, removed) do
    HologramEcosystemTestsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
