defmodule HologramFeatureTests.Realtime.Page1 do
  use Hologram.Page

  route "/realtime/1"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, server) do
    {
      put_state(component, :received, "none"),
      put_subscription(server, {:room, 1})
    }
  end

  def template do
    ~HOLO"""
    <p>Received: <strong id="received">{@received}</strong></p>
    """
  end

  def action(:show, params, component) do
    put_state(component, :received, params[:message])
  end
end
