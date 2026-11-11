defmodule Hologram.Test.Fixtures.Template.Renderer.Module95 do
  use Hologram.Component

  prop :a, :map

  @impl Component
  def template do
    ~HOLO"""
    a_b = {@a.b}
    """
  end
end
