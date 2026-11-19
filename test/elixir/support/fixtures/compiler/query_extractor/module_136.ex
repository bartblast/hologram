# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module136 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module16, as: Entity16
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :row, Entity2

  derived :rows, [Entity16], fn row -> include(Entity16, [^row.c]) end

  @impl Component
  def template do
    ~HOLO""
  end
end
