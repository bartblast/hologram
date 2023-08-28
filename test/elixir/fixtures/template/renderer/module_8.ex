defmodule Hologram.Test.Fixtures.Template.Renderer.Module8 do
  use Hologram.Component

  @impl Component
  def template do
    ~H"""
    abc<slot />xyz
    """
  end
end
