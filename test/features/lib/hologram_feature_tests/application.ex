defmodule HologramFeatureTests.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    children = [
      HologramFeatureTestsWeb.Telemetry,
      {Phoenix.PubSub, name: HologramFeatureTests.PubSub},
      HologramFeatureTestsWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: HologramFeatureTests.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl Application
  def config_change(changed, _new, removed) do
    HologramFeatureTestsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
