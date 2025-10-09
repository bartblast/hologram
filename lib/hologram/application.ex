defmodule Hologram.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    env = Hologram.env()
    mode = Application.get_env(:hologram, :mode, :embedded)
    opts = [strategy: :one_for_one, name: Hologram.Supervisor]

    mode
    |> children(env)
    |> Supervisor.start_link(opts)
  end

  # credo:disable-for-lines:13 Credo.Check.Readability.SinglePipe
  defp children(mode, env) do
    [
      if(mode == :standalone, do: {Bandit, plug: Hologram.HTTP}),
      {Phoenix.PubSub, name: Hologram.PubSub},
      Hologram.Router.PageModuleResolver,
      Hologram.Assets.PathRegistry,
      Hologram.Assets.ManifestCache,
      Hologram.Assets.PageDigestRegistry,
      if(env == :dev, do: Hologram.LiveReload)
    ]
    |> Enum.filter(& &1)
  end
end
