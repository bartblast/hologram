# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module107 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  derived :ripe, [Entity2], fn -> filter(Entity2, a: true) end

  @impl Component
  def template do
    ~HOLO""
  end
end
