# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module124 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module56
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :min_b, :integer

  derived :rows, [Entity2], fn min_b -> Module56.strictly_sized(min_b, 0) end

  @impl Component
  def template do
    ~HOLO""
  end
end
