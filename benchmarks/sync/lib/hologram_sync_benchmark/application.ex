defmodule HologramSyncBenchmark.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    children =
      hologram_children() ++
        [
          {Phoenix.PubSub, name: HologramSyncBenchmark.PubSub},
          HologramSyncBenchmarkWeb.Endpoint
        ]

    opts = [strategy: :one_for_one, name: HologramSyncBenchmark.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl Application
  def config_change(changed, _new, removed) do
    HologramSyncBenchmarkWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Hologram's mix.exs names its application callback only when it is built from a
  # `deps/hologram` folder, and this app takes it by path, so starting :hologram starts nothing.
  # Its supervisor is started here instead, ahead of the endpoint, as the callback would have
  # started it before this app. Drop this once #1630 is fixed.
  #
  # Only on the server node, the one whose endpoint serves: the driver booting Hologram would make
  # it a second node syncing against the same database, and would claim the database for the
  # driver's env, which the server node's env then refuses.
  defp hologram_children do
    endpoint_config =
      Application.fetch_env!(:hologram_sync_benchmark, HologramSyncBenchmarkWeb.Endpoint)

    # An app with no callback names `[]` as its :mod, not nil.
    if endpoint_config[:server] and Application.spec(:hologram, :mod) in [nil, []] do
      [
        %{
          id: Hologram.Supervisor,
          start: {Hologram.Application, :start, [:normal, []]},
          type: :supervisor
        }
      ]
    else
      []
    end
  end
end
