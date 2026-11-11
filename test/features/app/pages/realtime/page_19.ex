defmodule HologramFeatureTests.Realtime.Page19 do
  use Hologram.Page

  alias HologramFeatureTests.Realtime.Component6

  route "/realtime/19/:room"

  param :room, :integer

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <Component6 cid="widget" room={@room} />
    """
  end
end
