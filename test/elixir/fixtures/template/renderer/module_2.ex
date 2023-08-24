defmodule Hologram.Test.Fixtures.Template.Renderer.Module2 do
  use Hologram.Component

  @impl Component
  def template do
    ~H"""
    <div>prop_a = {@a}, prop_b = {@b}, prop_c = {@c}</div>
    """
  end
end
