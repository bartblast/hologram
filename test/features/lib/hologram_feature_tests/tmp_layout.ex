defmodule HologramFeatureTests.TmpLayout do
  use Hologram.Component
  alias Hologram.UI.Runtime

  def template do
    ~H"""
    <Runtime />
    layout
    <slot />
    """
  end
end
