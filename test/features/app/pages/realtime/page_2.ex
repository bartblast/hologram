defmodule HologramFeatureTests.Realtime.Page2 do
  use Hologram.Page

  route "/realtime/2"

  layout HologramFeatureTests.Components.DefaultLayout

  @channel_1 {:room, 1}
  @channel_2 {:room, 2}

  def init(_params, component, server) do
    new_component =
      component
      |> put_state(:received_1, "none")
      |> put_state(:received_2, "none")

    new_server =
      server
      |> put_subscription(@channel_1)
      |> put_subscription(@channel_2)

    {new_component, new_server}
  end

  def template do
    ~HOLO"""
    <p>Channel 1: <strong id="received-1">{@received_1}</strong></p>
    <p>Channel 2: <strong id="received-2">{@received_2}</strong></p>
    <button $click={command: :unsubscribe_and_broadcast}> Unsubscribe and broadcast </button>
    """
  end

  def action(:show_1, params, component) do
    put_state(component, :received_1, params[:message])
  end

  def action(:show_2, params, component) do
    put_state(component, :received_2, params[:message])
  end

  def command(:unsubscribe_and_broadcast, _params, server) do
    server
    |> delete_subscription(@channel_1)
    |> put_broadcast(@channel_1, :show_1, message: "delivered")
    |> put_broadcast(@channel_2, :show_2, message: "delivered")
  end
end
