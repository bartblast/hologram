defmodule Hologram.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    opts = [strategy: :one_for_one, name: Hologram.Supervisor]

    Hologram.env()
    |> children()
    |> Supervisor.start_link(opts)
  end

  defp children(:dev) do
    if Hologram.enabled?() do
      # The task supervisor comes first: Hologram.LiveReload runs each live reload pass under it,
      # unlinked, so that a pass that fails is logged instead of taking the watcher down with it.
      base_children() ++
        [{Task.Supervisor, name: Hologram.LiveReload.TaskSupervisor}, Hologram.LiveReload]
    else
      []
    end
  end

  defp children(_env) do
    if Hologram.enabled?() do
      base_children()
    else
      []
    end
  end

  defp base_children do
    [
      {Phoenix.PubSub, name: Hologram.PubSub},
      Hologram.Router.PageModuleResolver,
      Hologram.Assets.PathRegistry,
      Hologram.Assets.ManifestCache,
      Hologram.Assets.PageDigestRegistry,
      Hologram.Realtime.Handshake,
      Hologram.Realtime.SubscriptionRegistry,
      Hologram.Realtime.Tombstone
    ]
  end
end
