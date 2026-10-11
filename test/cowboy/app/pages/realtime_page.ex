defmodule HologramCowboyTests.RealtimePage do
  use Hologram.Page

  route "/realtime"

  layout HologramCowboyTests.Components.DefaultLayout

  @channel {:room, 1}

  def init(_params, component, server) do
    {
      put_state(component, :received, "none"),
      put_subscription(server, @channel)
    }
  end

  def template do
    ~HOLO"""
    <p>Received: <strong id="received">{@received}</strong></p>
    <button id="broadcast" $click={command: :broadcast}>Broadcast</button>
    """
  end

  def action(:show, params, component) do
    put_state(component, :received, params[:message])
  end

  def command(:broadcast, _params, server) do
    put_broadcast(server, @channel, :show, message: "delivered from a handler")
  end
end
