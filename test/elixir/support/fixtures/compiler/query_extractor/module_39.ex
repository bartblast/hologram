# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module39 do
  use Hologram.Component
  use Hologram.Query

  alias Hologram.Test.Fixtures.Entity.Module13, as: Entity13

  prop :entity, Entity13
  prop :entities, [Entity13], from_query: &entities_query/1

  @impl Component
  def template do
    ~HOLO""
  end

  defp entities_query(entity) do
    entity.type
    |> filter(title: "x")
    |> include(entity.rel)
  end
end
