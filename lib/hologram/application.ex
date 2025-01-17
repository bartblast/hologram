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

  defp all_envs_children do
    [
      Hologram.Router.PageModuleResolver,
      Hologram.Assets.PathRegistry,
      Hologram.Assets.ManifestCache,
      Hologram.Assets.PageDigestRegistry
    ]
  end

  defp children(:dev) do
    # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
    all_envs_children() ++ [Hologram.LiveReload]
  end

  defp children(_env), do: all_envs_children()
end
