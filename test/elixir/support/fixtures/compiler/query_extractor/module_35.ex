# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module35 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module4, as: Entity4

  prop :entity, Entity4
  prop :entities, [Entity4], from_query: &entities_query/1

  @impl Component
  def template do
    ~HOLO""
  end

  defp entities_query(entity) do
    filter(entity.type, no_entity_declares_this: 1)
  end
end
