defmodule HologramFeatureTests.Realtime.Page24 do
  use Hologram.Page

  alias Hologram.UI.Link
  alias HologramFeatureTests.Realtime.Page25

  route "/realtime/24"

  layout HologramFeatureTests.Components.RealtimeEchoLayout

  def template do
    ~HOLO"""
    <h1>Page 24</h1>
    <button $click={command: :broadcast_slowly}>Broadcast slowly</button>
    <Link to={Page25}>Go to Page 25</Link>
    """
  end

  # Stands in for a slow write: the reply, and the self echo in it, are still in flight after the
  # user has navigated to Page 25, so the page that sent the command has been left by the time it
  # lands.
  def command(:broadcast_slowly, _params, server) do
    Process.sleep(3_000)
    put_broadcast(server, {:room, 24}, :show, message: "echoed")
  end
end
