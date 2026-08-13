defmodule HologramFeatureTests.Realtime.Page23 do
  use Hologram.Page

  route "/realtime/23"

  layout HologramFeatureTests.Components.DefaultLayout

  @channel {:room, 23}

  # The action queued here is scheduled as soon as the page mounts, so the command it
  # issues reaches the server while the SSE handshake is still in flight. A subscription
  # declared from that command is the boot-time race this page exists to exercise.
  def init(_params, component, _server) do
    component
    |> put_state(:received, "none")
    |> put_action(:join)
  end

  def template do
    ~HOLO"""
    <p>Received: <strong id="received">{@received}</strong></p>
    """
  end

  def action(:join, _params, component) do
    put_command(component, :subscribe)
  end

  def action(:show, params, component) do
    put_state(component, :received, params[:message])
  end

  def command(:subscribe, _params, server) do
    put_subscription(server, @channel)
  end
end
