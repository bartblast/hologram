defmodule HologramFeatureTests.Realtime.Component2 do
  use Hologram.Component

  @channel_1 {:room, 1}

  def init(_props, component, server) do
    {
      put_state(component, :received, "none"),
      put_subscription(server, @channel_1)
    }
  end

  def template do
    ~HOLO"""
    <p>Component 2: <strong id="received-component-2">{@received}</strong></p>
    """
  end

  def action(:show, params, component) do
    put_state(component, :received, params[:message])
  end
end
