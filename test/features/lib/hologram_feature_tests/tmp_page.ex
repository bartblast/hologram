defmodule HologramFeatureTests.TmpPage do
  use Hologram.Page

  route "/abc"

  layout HologramFeatureTests.TmpLayout

  def template do
    ~H"""
    page
    """
  end
end
