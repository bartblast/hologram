defmodule Hologram.Test.Fixtures.Template.Renderer.Module158 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module25, as: Entity25

  derived :entities, [Entity25], fn -> filter(Entity25, h.title != "nothing") end

  @impl Component
  def template do
    ~HOLO"""
    h = {Enum.map_join(@entities, ",", &inspect(&1.h))}
    """
  end
end
