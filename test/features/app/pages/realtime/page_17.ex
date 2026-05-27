defmodule HologramFeatureTests.Realtime.Page17 do
  use Hologram.Page

  alias HologramFeatureTests.Realtime.Component5

  route "/realtime/17"

  layout HologramFeatureTests.Components.DefaultLayout

  @channel {:room, 17}

  def init(_params, _component, server) do
    put_subscription(server, @channel)
  end

  def template do
    ~HOLO"""
    <Component5 cid="component_5" />
    """
  end
end
