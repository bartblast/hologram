defmodule Hologram.Test.Fixtures.Template.Renderer.Module87 do
  use Hologram.Component

  alias Hologram.Test.Fixtures.Template.Renderer.Module32

  @impl Component
  def template do
    ~HOLO"""
    87a,<Module32>87b,<{"div"}><slot /></{"div"}>,87x,</Module32>87z
    """
  end
end
