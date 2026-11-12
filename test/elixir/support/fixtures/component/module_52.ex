# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Component.Module52 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  derived :entities, [Entity2], fn -> trust(Entity2) end

  @impl Component
  def template do
    ~HOLO""
  end
end
