# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module85 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  derived :first, Entity2, fn -> one(filter(Entity2, a == true)) end

  derived :narrowed, [Entity2], fn first -> filter(first.self, a == true) end

  @impl Component
  def template do
    ~HOLO""
  end
end
