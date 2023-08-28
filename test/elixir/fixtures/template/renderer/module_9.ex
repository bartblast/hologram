defmodule Hologram.Test.Fixtures.Template.Renderer.Module9 do
  use Hologram.Component

  @impl Component
  def template do
    ~H"""
    def<slot />uvw
    """
  end
end
