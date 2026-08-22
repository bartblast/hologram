# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Benchmarks.Fixtures.Components.EntityPropComponent do
  @moduledoc false

  use Hologram.Component
  use Hologram.Query

  alias Hologram.Benchmarks.Fixtures.Entity1

  prop :entities, [Entity1], from_query: &entities_query/1
  prop :entity, Entity1

  def template do
    ~HOLO""
  end

  defp entities_query(entity) do
    filter(entity.type, position: {:>=, 1})
  end
end
