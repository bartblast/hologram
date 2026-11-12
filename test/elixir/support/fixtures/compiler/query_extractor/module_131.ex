# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module131 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module79
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  derived :bound_entity, [Entity2], fn ->
    entity = Entity2
    entity
  end

  derived :bound_entity_label, :string, fn ->
    entity = Entity2
    inspect(entity)
  end

  derived :bound_helper_entity, [Entity2], fn ->
    entity = Module79.entity_type()
    entity
  end

  derived :chained_bound_entity, [Entity2], fn ->
    entity = _other = Entity2
    entity
  end

  derived :helper_bound_entity, [Entity2], fn -> bound_entity_type() end

  derived :tail_bound_entity, [Entity2], fn -> _entity = Entity2 end

  @impl Component
  def template do
    ~HOLO""
  end

  defp bound_entity_type do
    entity = Entity2
    entity
  end
end
