defmodule Hologram.Runtime.Application do
  @moduledoc false

  use Application
  alias Hologram.Runtime.{PageDigestStore, TemplateStore, Watcher}

  @env Application.fetch_env!(:hologram, :env)

  @impl true
  def start(_type, _args) do
    children = [
      PageDigestStore,
      TemplateStore
    ]

    children =
      if @env == :dev do
        children ++ [Watcher]
      else
        children
      end

    opts = [strategy: :one_for_one, name: Hologram.Runtime.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
