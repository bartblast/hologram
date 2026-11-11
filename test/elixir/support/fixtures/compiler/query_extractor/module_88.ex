# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module88 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :entity_type, :atom

  derived :titled, [Entity2], fn entity_type -> filter(entity_type, title == "x") end

  @impl Component
  def template do
    ~HOLO""
  end
end
