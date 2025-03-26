# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module1 do
  use Hologram.Component

  @impl Component
  def template do
    ~HOLO"""
    <div>abc</div>
    """
  end
end
