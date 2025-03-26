defmodule Hologram.Test.Fixtures.Template.Renderer.Module8 do
  use Hologram.Component

  @impl Component
  def template do
    ~HOLO"""
    abc<slot />xyz
    """
  end
end
