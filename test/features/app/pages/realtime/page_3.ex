defmodule HologramFeatureTests.Realtime.Page3 do
  use Hologram.Page

  alias Hologram.UI.Link
  alias HologramFeatureTests.Realtime.Page4

  route "/realtime/3"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, _component, server) do
    put_subscription(server, {:room, 1})
  end

  def template do
    ~HOLO"""
    <h1>Page 3</h1>
    <Link to={Page4}>Go to Page 4</Link>
    """
  end
end
