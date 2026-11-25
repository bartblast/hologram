defmodule HologramSyncBenchmark.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: HologramSyncBenchmark.PubSub},
      HologramSyncBenchmarkWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: HologramSyncBenchmark.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl Application
  def config_change(changed, _new, removed) do
    HologramSyncBenchmarkWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
