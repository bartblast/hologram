defmodule Hologram.Test.Fixtures.Template.Renderer.Module49 do
  use Hologram.Layout
  alias Hologram.UI.Runtime

  @impl Layout
  def template do
    ~H"""
    layout template start
    <Runtime />
    <slot />
    layout template end
    """
  end
end
