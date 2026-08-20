# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module37 do
  use Hologram.Component
  use Hologram.Query

  alias Hologram.Test.Fixtures.Entity.Module3, as: Entity3

  prop :entity, Entity3
  prop :entities, [Entity3], from_query: &entities_query/1

  @impl Component
  def template do
    ~HOLO""
  end

  defp entities_query(entity) do
    include(Entity3, entity.rel)
  end
end
