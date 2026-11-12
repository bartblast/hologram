# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module132 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :row, Entity2

  derived :bumped, Entity2, fn row -> increment(row, :b, 1) end

  derived :edited, Entity2, fn row -> put_attribute(row, :c, "edited") end

  derived :trusted_entity_type, [Entity2], fn -> trust(Entity2) end

  derived :trusted_row, Entity2, fn row -> trust(row) end

  @impl Component
  def template do
    ~HOLO""
  end
end
