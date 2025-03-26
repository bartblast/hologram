defmodule Hologram.Test.Fixtures.Template.Renderer.Module17 do
  use Hologram.Component

  prop :a, :string

  @impl Component
  def template do
    ~HOLO"""
    var_a = {@a}, var_b = {@b}
    """
  end
end
