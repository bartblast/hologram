defmodule Hologram.Application do
  use Application

  @impl Application
  def start(_type, _args) do
    # TODO: add children
    children = []

    opts = [strategy: :one_for_one, name: Hologram.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
