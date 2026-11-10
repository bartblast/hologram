defmodule Hologram.Test.Fixtures.Template.Renderer.Module114 do
  use Hologram.Component

  alias Hologram.Test.Fixtures.Template.Renderer.Module8

  @impl Component
  def template do
    ~HOLO"""
    <Module8><slot /></Module8>
    """
  end
end
