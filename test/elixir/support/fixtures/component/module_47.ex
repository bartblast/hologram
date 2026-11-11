# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Component.Module47 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module25, as: Entity25

  derived :entities, [Entity25], fn -> filter(Entity25, g.token == "tok_hidden") end

  @impl Component
  def template do
    ~HOLO""
  end
end
