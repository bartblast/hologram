defmodule Hologram.Test.Fixtures.Template.Renderer.Module54 do
  use Hologram.Component
  alias Hologram.UI.Runtime

  @impl Component
  def template do
    ~H"""
    <Runtime />
    """
  end
end
