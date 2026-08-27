# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Component.Module7 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :entities, [Entity2], from_query: &entities_query/0

  @impl Component
  def template do
    ~HOLO""
  end

  defp entities_query do
    filter(Entity2, a: true)
  end
end
