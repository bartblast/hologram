# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module97 do
  use Hologram.Component

  def read_b(map), do: map.b

  @impl Component
  def template do
    ~HOLO"""
    b = {read_b(:maps.from_list([]))}
    """
  end
end
