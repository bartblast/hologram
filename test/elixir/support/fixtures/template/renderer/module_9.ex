defmodule Hologram.Test.Fixtures.Template.Renderer.Module9 do
  use Hologram.Component

  @impl Component
  def template do
    ~HOLO"""
    def<slot />uvw
    """
  end
end
