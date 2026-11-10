defmodule Hologram.Test.Fixtures.Template.Renderer.Module117 do
  use Hologram.Component

  alias Hologram.Test.Fixtures.Template.Renderer.Module8

  @impl Component
  def template do
    ~HOLO"""
    <Module8><slot /><slot /></Module8>
    """
  end
end
