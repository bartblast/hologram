# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Component.Module23 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :entities, [Entity2], from_query: &entities_query/1

  @impl Component
  def template do
    ~HOLO""
  end

  # Every clause fixes the argument with a literal, so no clause names the position - the capture
  # has no argument name to bind a prop by.
  defp entities_query(0) do
    filter(Entity2, a: true)
  end

  defp entities_query(1) do
    filter(Entity2, a: false)
  end
end
