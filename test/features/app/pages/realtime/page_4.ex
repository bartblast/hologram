defmodule HologramFeatureTests.Realtime.Page4 do
  use Hologram.Page

  alias Hologram.UI.Link

  route "/realtime/4"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, server) do
    new_component =
      component
      |> put_state(:received_1, "none")
      |> put_state(:received_2, "none")

    new_server = put_subscription(server, {:room, 2})

    {new_component, new_server}
  end

  def template do
    ~HOLO"""
    <h1>Page 4</h1>
    <p>Channel 1: <strong id="received-1">{@received_1}</strong></p>
    <p>Channel 2: <strong id="received-2">{@received_2}</strong></p>
    <button $click={command: :broadcast}>Broadcast</button>
    """
  end

  def action(:show_1, params, component) do
    put_state(component, :received_1, params[:message])
  end

  def action(:show_2, params, component) do
    put_state(component, :received_2, params[:message])
  end

  def command(:broadcast, _params, server) do
    server
    |> put_broadcast({:room, 1}, :show_1, message: "delivered")
    |> put_broadcast({:room, 2}, :show_2, message: "delivered")
  end
end
