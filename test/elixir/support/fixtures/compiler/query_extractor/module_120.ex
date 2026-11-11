# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module120 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :row, Entity2

  derived :rows, [Entity2], fn row -> filter(Entity2, ^row.preds) end

  @impl Component
  def template do
    ~HOLO""
  end
end
