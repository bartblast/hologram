defmodule HologramFeatureTests.Realtime.Page11 do
  use Hologram.Page

  route "/realtime/11"

  layout HologramFeatureTests.Components.DefaultLayout

  @channel_1 {:room, 1}

  def init(_params, component, _server) do
    put_state(component, :received, "none")
  end

  def template do
    ~HOLO"""
    <p>Received: <strong id="received">{@received}</strong></p>
    <button $click={command: :subscribe}>Subscribe</button>
    """
  end

  def action(:show, params, component) do
    put_state(component, :received, params[:message])
  end

  def command(:subscribe, _params, server) do
    put_subscription(server, @channel_1)
  end
end
