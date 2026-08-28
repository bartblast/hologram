# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module97 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :entities, [Entity2], from_query: &entities_query/0

  @impl Component
  def template do
    ~HOLO"""
    entities = {Enum.map_join(@entities, ",", & &1.c)}
    """
  end

  defp entities_query do
    Entity2
    |> filter(a: true)
    |> order_by(:c)
  end
end
