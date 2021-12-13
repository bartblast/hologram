defmodule Hologram.Runtime.Application do
  @moduledoc false

  use Application

  @env Application.fetch_env!(:hologram, :env)

  @impl true
  def start(_type, _args) do
    children = [
      Hologram.Compiler.TemplateStore
    ]

    children =
      if @env == :dev do
        children ++ [Hologram.Runtime.Watcher]
      else
        children
      end

    opts = [strategy: :one_for_one, name: Hologram.Runtime.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
