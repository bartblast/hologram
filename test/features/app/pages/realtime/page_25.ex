defmodule HologramFeatureTests.Realtime.Page25 do
  use Hologram.Page

  route "/realtime/25"

  layout HologramFeatureTests.Components.RealtimeEchoLayout

  def template do
    ~HOLO"""
    <h1>Page 25</h1>
    """
  end
end
