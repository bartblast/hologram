defmodule Hologram.Test.Fixtures.Template.Renderer.Module33 do
  use Hologram.Component

  @impl Component
  def template do
    ~HOLO"""
    33a,<slot />33z,
    """
  end
end
