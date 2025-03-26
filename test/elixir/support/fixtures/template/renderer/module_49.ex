defmodule Hologram.Test.Fixtures.Template.Renderer.Module49 do
  use Hologram.Component
  alias Hologram.UI.Runtime

  @impl Component
  def template do
    ~HOLO"""
    layout template start
    <Runtime />
    <slot />
    layout template end
    """
  end
end
