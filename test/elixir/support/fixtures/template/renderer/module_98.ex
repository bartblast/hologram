defmodule Hologram.Test.Fixtures.Template.Renderer.Module98 do
  use Hologram.Component

  @impl Component
  def template do
    ~HOLO"""
    b = {:maps.from_list([]).b}
    """
  end
end
