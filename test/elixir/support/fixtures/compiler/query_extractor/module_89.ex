# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module89 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :entity_type, :atom

  derived :unknown, [Entity2], fn entity_type ->
    filter(entity_type, no_entity_declares_this == true)
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
