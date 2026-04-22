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
    if start_children?() do
      # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
      base_children() ++ [Hologram.LiveReload]
    else
      []
    end
  end

  defp children(_env) do
    if start_children?() do
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
      Hologram.Assets.PageDigestRegistry
    ]
  end

  defp start_children? do
    Hologram.env() not in [:dev, :test] or System.get_env("HOLOGRAM_START") == "1"
  end
end
