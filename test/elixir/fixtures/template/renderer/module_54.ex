defmodule Hologram.Test.Fixtures.Template.Renderer.Module54 do
  use Hologram.Layout
  alias Hologram.UI.Runtime

  @impl Layout
  def template do
    ~H"""
    <Runtime />
    """
  end
end
