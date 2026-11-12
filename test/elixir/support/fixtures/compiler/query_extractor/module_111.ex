# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module111 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module4, as: Entity4

  prop :relation, :atom

  derived :rows, [Entity4], fn relation -> include(Entity4, ^relation) end

  @impl Component
  def template do
    ~HOLO""
  end
end
