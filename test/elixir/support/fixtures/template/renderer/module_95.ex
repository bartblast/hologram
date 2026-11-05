defmodule Hologram.Test.Fixtures.Template.Renderer.Module95 do
  use Hologram.Component

  @impl Component
  def template do
    ~HOLO"""
    <textarea><slot /></textarea>
    """
  end
end
