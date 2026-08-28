# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module12 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :entities, [Entity2], from_query: &entities_query/0

  @impl Component
  def template do
    ~HOLO""
  end

  def entities_query do
    min_b = 100

    if Enum.member?([50, 100], min_b) do
      filter(Entity2, b: {:>=, min_b})
    else
      filter(Entity2, a: true)
    end
  end
end
