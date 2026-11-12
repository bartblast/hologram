# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Component.Module41 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :min_b, :integer

  derived :entities, [Entity2], fn min_b -> filter(Entity2, b >= ^min_b) end

  @impl Component
  def template do
    ~HOLO""
  end
end
