defmodule Hologram.Test.Fixtures.Template.Renderer.Module124 do
  use Hologram.Component

  @impl Component
  def template do
    ~HOLO"""
    var_c = {@c}
    """
  end
end
