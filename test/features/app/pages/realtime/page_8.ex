defmodule HologramFeatureTests.Realtime.Page8 do
  use Hologram.Page

  alias HologramFeatureTests.Realtime.Component1
  alias HologramFeatureTests.Realtime.Component2

  route "/realtime/8"

  layout HologramFeatureTests.Components.DefaultLayout

  @channel_1 {:room, 1}
  @channel_2 {:room, 2}

  def init(_params, component, server) do
    {
      put_state(component, :received, "none"),
      put_subscription(server, @channel_2)
    }
  end

  def template do
    ~HOLO"""
    <p>Channel 2: <strong id="received-page">{@received}</strong></p>
    <Component1 cid="component_1" />
    <Component2 cid="component_2" />
    <button $click={command: :broadcast}>Broadcast</button>
    """
  end

  def action(:show, params, component) do
    put_state(component, :received, params[:message])
  end

  def command(:broadcast, _params, server) do
    server
    |> put_broadcast(@channel_1, :show, message: "delivered")
    |> put_broadcast(@channel_2, :show, message: "delivered")
  end
end
