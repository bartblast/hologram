# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Component.Module8 do
  use Hologram.Component

  import Hologram.Test.Fixtures.Component.Module9, only: [shared_query: 0]

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :entities, [Entity2], from_query: &shared_query/0

  @impl Component
  def template do
    ~HOLO""
  end
end
