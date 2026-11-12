# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Component.Module45 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module3, as: Entity3

  derived :entities, [Entity3], fn -> filter(Entity3, c.id != nil) end

  @impl Component
  def template do
    ~HOLO""
  end
end
