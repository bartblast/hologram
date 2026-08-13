defmodule HologramClusterTests.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: HologramClusterTests.PubSub},
      HologramClusterTestsWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: HologramClusterTests.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl Application
  def config_change(changed, _new, removed) do
    HologramClusterTestsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
