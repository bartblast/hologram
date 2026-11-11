# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Component.Module43 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module1, as: Entity1

  derived :entities, [Entity1], fn -> filter(Entity1, []) end

  @impl Component
  def template do
    ~HOLO""
  end
end
