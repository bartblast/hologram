# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Component.Module54 do
  use Hologram.Component

  alias Hologram.Test.Fixtures.Component.Module55
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :min_b, :integer

  derived :entities, [Entity2], fn min_b -> Module55.bounded(min_b) end

  @impl Component
  def template do
    ~HOLO""
  end
end
