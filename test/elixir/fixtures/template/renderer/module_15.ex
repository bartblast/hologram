defmodule Hologram.Test.Fixtures.Template.Renderer.Module15 do
  use Hologram.Layout

  @impl Layout
  def template do
    ~H"""
    layout template start, <slot />, layout template end
    """
  end
end
