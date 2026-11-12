# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module130 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :_min_b, :integer

  derived :entities, [Entity2], fn _min_b -> filter(Entity2, a == true) end

  @impl Component
  def template do
    ~HOLO""
  end
end
