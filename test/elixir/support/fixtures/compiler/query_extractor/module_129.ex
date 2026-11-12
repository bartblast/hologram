# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module129 do
  use Hologram.Component

  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module19
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :min_b, :integer

  derived :entities, [Entity2], fn min_b -> Module19.bounded_query(min_b) end

  @impl Component
  def template do
    ~HOLO""
  end
end
