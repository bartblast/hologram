# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module105 do
  use Hologram.Component
  use Hologram.Query

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :entities, [Entity2], from_query: &entities_query/1
  prop :min_b, :integer

  @impl Component
  def template do
    ~HOLO"""
    entities = {Enum.map_join(@entities, ",", & &1.c)}
    """
  end

  defp entities_query(min_b) do
    Entity2
    |> filter(b: {:>=, min_b})
    |> order_by(:c)
  end
end
