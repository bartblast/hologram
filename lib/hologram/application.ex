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

  # Use compile-time conditional compilation because Hologram.env() returns a compile-time
  # constant (module attribute). Pattern matching would cause "unused clause" warnings,
  # and runtime conditionals would cause Dialyzer warnings about unreachable code.
  if Hologram.env() == :dev do
    defp children(_env) do
      # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
      all_envs_children() ++ [Hologram.LiveReload]
    end
  else
    defp children(_env), do: all_envs_children()
  end
end
