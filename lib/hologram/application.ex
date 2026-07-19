defmodule Hologram.Application do
  @moduledoc false

  use Application

  alias Hologram.Reflection

  @impl Application
  def start(_type, _args) do
    opts = [strategy: :one_for_one, name: Hologram.Supervisor]

    Hologram.env()
    |> children()
    |> Supervisor.start_link(opts)
  end

  defp children(:dev) do
    if Hologram.enabled?() do
      # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
      base_children() ++ [Hologram.LiveReload]
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
    # The database goes first - it must be running before anything that serves requests.
    database_children() ++
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

  # The database is activated by the data model: it starts exactly when the app declares
  # entity types, with no host-app ceremony.
  defp database_children do
    if Reflection.list_entities() == [] do
      []
    else
      [Hologram.Database]
    end
  end
end
