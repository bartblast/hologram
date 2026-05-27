defmodule HologramFeatureTests.Realtime.Page10 do
  use Hologram.Page

  route "/realtime/10"

  layout HologramFeatureTests.Components.DefaultLayout

  @channel_1 {:room, 1}
  @user_id 1

  def init(_params, component, server) do
    {
      put_state(component, :received, "none"),
      put_subscription(server, @channel_1)
    }
  end

  def template do
    ~HOLO"""
    <p>Received: <strong id="received">{@received}</strong></p>
    <button $click={command: :log_in}>Log in</button>
    <button $click={command: :log_out}>Log out</button>
    """
  end

  def action(:show, params, component) do
    put_state(component, :received, params[:message])
  end

  def command(:log_in, _params, server) do
    Map.put(server, :user_id, @user_id)
  end

  def command(:log_out, _params, server) do
    Map.put(server, :user_id, nil)
  end
end
