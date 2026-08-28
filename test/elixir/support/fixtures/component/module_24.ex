# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Component.Module24 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :entities, [Entity2], from_query: &entities_query/1
  prop :min_b, :integer

  @impl Component
  def template do
    ~HOLO""
  end

  defp entities_query(min_b) do
    filter(Entity2, b: {:>=, min_b})
  end
end
