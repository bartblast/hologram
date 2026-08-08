# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module12 do
  use Hologram.Component
  use Hologram.Query

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :entities, [Entity2], from_query: &entities_query/0

  @impl Component
  def template do
    ~HOLO""
  end

  def entities_query do
    min_b = String.length("three-digit bound")

    if min_b > 10 do
      filter(Entity2, b: {:>=, min_b})
    else
      filter(Entity2, a: true)
    end
  end
end
