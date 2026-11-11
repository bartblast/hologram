defmodule Hologram.Test.Fixtures.Template.Renderer.Module115 do
  use Hologram.Component

  alias Hologram.Test.Fixtures.Template.Renderer.Module114

  @impl Component
  def template do
    ~HOLO"""
    <Module114><slot /></Module114>
    """
  end
end
