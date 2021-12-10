defmodule Hologram.Runtime.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Hologram.Compiler.TemplateStore
    ]

    children =
      if Mix.env() == :dev do
        children ++ [Hologram.Runtime.Watcher]
      else
        children
      end

    opts = [strategy: :one_for_one, name: Hologram.Runtime.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
