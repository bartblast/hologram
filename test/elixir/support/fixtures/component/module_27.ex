# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Component.Module27 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :min_b, :integer
  prop :entities, [Entity2], from_query: &first_query/1
  # Binds what the query above produced rather than anything the component was given.
  prop :derived, [Entity2], from_query: &second_query/1

  @impl Component
  def template do
    ~HOLO""
  end

  defp first_query(min_b) do
    filter(Entity2, b: {:>=, min_b})
  end

  defp second_query(entities) do
    filter(Entity2, a: entities)
  end
end
