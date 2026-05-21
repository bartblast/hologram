defmodule HologramFeatureTests.Realtime.Page2 do
  use Hologram.Page

  route "/realtime/2"

  layout HologramFeatureTests.Components.DefaultLayout

  @sync_channel {:room, 2}
  @test_channel {:room, 1}

  def init(_params, component, server) do
    new_component =
      component
      |> put_state(:received_sync, "none")
      |> put_state(:received_test, "none")

    new_server =
      server
      |> put_subscription(@sync_channel)
      |> put_subscription(@test_channel)

    {new_component, new_server}
  end

  def template do
    ~HOLO"""
    <p>Test: <strong id="received-test">{@received_test}</strong></p>
    <p>Sync: <strong id="received-sync">{@received_sync}</strong></p>
    <button $click={command: :unsubscribe}> Unsubscribe </button>
    """
  end

  def action(:show_sync, params, component) do
    put_state(component, :received_sync, params[:message])
  end

  def action(:show_test, params, component) do
    put_state(component, :received_test, params[:message])
  end

  def command(:unsubscribe, _params, server) do
    delete_subscription(server, @test_channel)
  end
end
