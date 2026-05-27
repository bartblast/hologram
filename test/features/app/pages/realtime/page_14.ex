defmodule HologramFeatureTests.Realtime.Page14 do
  use Hologram.Page

  route "/realtime/14"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, server) do
    put_state(component,
      broadcasts: inspect(server.broadcasts),
      subscriptions: inspect(server.subscriptions)
    )
  end

  def template do
    ~HOLO"""
    <p>Broadcasts: <strong id="broadcasts-page">{@broadcasts}</strong></p>
    <p>Subscriptions: <strong id="subscriptions-page">{@subscriptions}</strong></p>
    """
  end
end
