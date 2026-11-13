defmodule Hologram.Test.Fixtures.Template.Renderer.Module176 do
  use Hologram.Component

  @impl Component
  def template do
    ~HOLO"""
    b = {:maps.from_list([]).b}
    """
  end
end
