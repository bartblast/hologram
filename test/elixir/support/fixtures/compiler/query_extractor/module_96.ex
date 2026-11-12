# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module96 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  derived :rows, [Entity2], fn ->
    Enum.map([true, false], fn wanted -> filter(Entity2, a == ^wanted) end)

    Entity2
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
