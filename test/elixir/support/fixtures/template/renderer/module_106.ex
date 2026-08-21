# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module106 do
  use Hologram.Component
  use Hologram.Query

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :entities, [Entity2], from_query: &entities_query/1

  @impl Component
  def template do
    ~HOLO"""
    entities = {inspect(@entities)}
    """
  end

  defp entities_query(missing_prop) do
    filter(Entity2, b: {:>=, missing_prop})
  end
end
