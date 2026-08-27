# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module6 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :entities, [Entity2], from_query: &__MODULE__.entities_query/2

  @impl Component
  def template do
    ~HOLO""
  end

  def entities_query(min_b, search) do
    filter(Entity2, b: {:>=, min_b}, c: search)
  end
end
