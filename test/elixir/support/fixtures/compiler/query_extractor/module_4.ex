# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module4 do
  use Hologram.Component

  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module5
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :entities, [Entity2], from_query: &Module5.entities_query/0

  @impl Component
  def template do
    ~HOLO""
  end
end
