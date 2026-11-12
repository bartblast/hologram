# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Component.Module44 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module3, as: Entity3

  derived :entities, [Entity3], fn -> include(Entity3, c) end

  @impl Component
  def template do
    ~HOLO""
  end
end
