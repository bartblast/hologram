# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module140 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module3, as: Entity3

  prop :a, :atom

  derived :rows, [Entity3], fn a -> include(a, [a]) end

  @impl Component
  def template do
    ~HOLO""
  end
end
