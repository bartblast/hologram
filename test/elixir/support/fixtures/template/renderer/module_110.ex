# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module110 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module25, as: Entity25

  prop :entities, [Entity25], from_query: &entities_query/0

  @impl Component
  def template do
    ~HOLO"""
    h = {Enum.map_join(@entities, ",", &inspect(&1.h))}
    """
  end

  defp entities_query do
    filter(Entity25, h.title != "nothing")
  end
end
