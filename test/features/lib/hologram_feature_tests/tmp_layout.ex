defmodule HologramFeatureTests.TmpLayout do
  use Hologram.Layout

  def template do
    ~H"""
    layout<slot />
    """
  end
end
