defmodule HologramFeatureTests.Realtime.Component4 do
  use Hologram.Component

  def init(_props, component, server) do
    put_state(component,
      broadcasts: inspect(server.broadcasts),
      subscriptions: inspect(server.subscriptions)
    )
  end

  def template do
    ~HOLO"""
    <p>Broadcasts: <strong id="broadcasts-component">{@broadcasts}</strong></p>
    <p>Subscriptions: <strong id="subscriptions-component">{@subscriptions}</strong></p>
    """
  end
end
