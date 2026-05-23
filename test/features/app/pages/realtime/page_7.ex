defmodule HologramFeatureTests.Realtime.Page7 do
  use Hologram.Page

  route "/realtime/7"

  layout HologramFeatureTests.Components.DefaultLayout

  @channel_1 {:room, 1}

  def init(_params, component, server) do
    {
      put_state(component, :received, "none"),
      put_subscription(server, @channel_1)
    }
  end

  def template do
    ~HOLO"""
    <p>Received: <strong id="received">{@received}</strong></p>
    <button $click={command: :broadcast}>Broadcast</button>
    <button $click={command: :broadcast_except_instance}>Exclude instance</button>
    <button $click={command: :broadcast_except_session}>Exclude session</button>
    """
  end

  def action(:show, params, component) do
    put_state(component, :received, params[:message])
  end

  def command(:broadcast, _params, server) do
    put_broadcast(server, @channel_1, :show, message: "delivered")
  end

  def command(:broadcast_except_instance, _params, server) do
    put_broadcast_except(server, {:instance, server.instance_id}, @channel_1, :show,
      message: "delivered to everyone else"
    )
  end

  def command(:broadcast_except_session, _params, server) do
    put_broadcast_except(server, {:session, server.session_id}, @channel_1, :show,
      message: "delivered to all other sessions"
    )
  end
end
