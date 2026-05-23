defmodule HologramFeatureTests.Realtime.Page11 do
  use Hologram.Page

  route "/realtime/11"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :received, "none")
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
