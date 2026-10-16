defmodule HologramMinimalTests.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: HologramMinimalTests.PubSub},
      HologramMinimalTestsWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: HologramMinimalTests.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl Application
  def config_change(changed, _new, removed) do
    HologramMinimalTestsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
