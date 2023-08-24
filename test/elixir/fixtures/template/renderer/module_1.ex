defmodule Hologram.Test.Fixtures.Template.Renderer.Module1 do
  use Hologram.Component

  @impl Component
  def template do
    ~H"""
    <div>abc</div>
    """
  end
end
