defmodule Hologram.Test.Fixtures.Template.Renderer.Module15 do
  use Hologram.Component

  @impl Component
  def template do
    ~HOLO"""
    layout template start, <slot />, layout template end
    """
  end
end
