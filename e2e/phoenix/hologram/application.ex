defmodule Hologram.E2E.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      Hologram.E2E.Web.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: Hologram.E2E.PubSub},
      # Start the Endpoint (http/https)
      Hologram.E2E.Web.Endpoint
      # Start a worker by calling: Hologram.Worker.start_link(arg)
      # {Hologram.Worker, arg}
    ]

    children =
      if Mix.env() == :dev do
        children ++ [Hologram.Runtime.Watcher]
      else
        children
      end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
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
