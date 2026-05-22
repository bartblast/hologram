defmodule HologramFeatureTests.Realtime.Page6 do
  use Hologram.Page

  route "/realtime/6"

  layout HologramFeatureTests.Components.RealtimeLayout

  def template do
    ~HOLO"""
    <h1>Page 6</h1>
    <button $click={command: :broadcast}>Broadcast</button>
    """
  end

  def command(:broadcast, _params, server) do
    put_broadcast(server, {:room, 9}, "layout", :show, message: "delivered")
  end
end
