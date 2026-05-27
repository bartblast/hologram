defmodule HologramFeatureTests.Realtime.Component3 do
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
    <p>Component 3: <strong id="received-component-3">{@received}</strong></p>
    <button $click={command: :unsubscribe_and_broadcast}>Unsubscribe and broadcast</button>
    """
  end

  def action(:show, params, component) do
    put_state(component, :received, params[:message])
  end

  def command(:unsubscribe_and_broadcast, _params, server) do
    server
    |> delete_subscription(@channel_1)
    |> put_broadcast(@channel_1, :show, message: "delivered to sibling cid")
  end
end
