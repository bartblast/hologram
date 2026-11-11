# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module117 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module4, as: Entity4

  prop :entity_type, :atom

  derived :rows, [Entity4], fn entity_type ->
    filter(entity_type, no_entity_declares_this >= 1 and no_entity_declares_this < 9)
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
