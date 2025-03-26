defmodule Hologram.Test.Fixtures.Template.Renderer.Module32 do
  use Hologram.Component

  @impl Component
  def template do
    ~HOLO"""
    32a,<slot />32z,
    """
  end
end
