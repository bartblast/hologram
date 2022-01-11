defmodule Hologram.Runtime.Application do
  @moduledoc false

  use Application

  alias Hologram.Runtime.{
    PageDigestStore,
    RouterBuilder,
    StaticDigestStore,
    TemplateStore,
    Watcher
  }

  @env Application.fetch_env!(:hologram, :env)

  @impl true
  def start(_type, _args) do
    opts = [strategy: :one_for_one, name: Hologram.Runtime.Supervisor]
    Supervisor.start_link(children(@env), opts)
  end

  defp children(:dev) do
    children(:prod) ++ [Watcher]
  end

  defp children(_) do
    [
      PageDigestStore,
      StaticDigestStore,
      RouterBuilder,
      TemplateStore
    ]
  end
end
