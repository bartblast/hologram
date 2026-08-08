# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Component.Module14 do
  use Hologram.Component

  alias Hologram.Test.Fixtures.Component.Module13
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :entities, [Entity2], from_query: &Module13.bounded_query/1

  @impl Component
  def template do
    ~HOLO""
  end
end
