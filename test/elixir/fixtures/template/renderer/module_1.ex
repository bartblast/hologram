# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module1 do
  use Hologram.Component

  def init(_props, component) do
    component
  end

  @impl Component
  def template do
    ~H"""
    <div>abc</div>
    """
  end
end
