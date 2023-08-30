defmodule Hologram.Test.Fixtures.Template.Renderer.Module17 do
  use Hologram.Component

  prop :a

  @impl Component
  def template do
    ~H"""
    var_a = {@a}, var_b = {@b}
    """
  end
end
