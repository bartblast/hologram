# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module161 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :min_b, :integer

  derived :entities, [Entity2], fn min_b ->
    Entity2
    |> filter(b >= ^min_b)
    |> sort(c)
  end

  @impl Component
  def template do
    ~HOLO"""
    entities = {Enum.map_join(@entities, ",", & &1.c)}
    """
  end
end
