defmodule HologramFeatureTests.TmpPage do
  use Hologram.Page

  route "/abc/:xyz"

  param :xyz

  layout HologramFeatureTests.TmpLayout

  def template do
    ~H"""
    page with param: {@xyz}
    """
  end
end
