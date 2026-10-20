# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module45 do
  use Hologram.Component

  alias Hologram.Query.Stage
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :entities, [Entity2], from_query: &entities_query/1

  @impl Component
  def template do
    ~HOLO""
  end

  # A stage called on the stage module itself rather than through a Hologram.Query delegate.
  defp entities_query(min_b) do
    Stage.filter(Entity2, b: {:>=, min_b})
  end
end
