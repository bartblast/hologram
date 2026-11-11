# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module121 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :min_b, :integer

  derived :rows, [Entity2], fn min_b ->
    Entity2
    |> filter(b >= ^min_b)
    |> filter(nonexistent: 1)
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
