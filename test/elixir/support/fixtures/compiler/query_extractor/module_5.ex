# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module5 do
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  def entities_query do
    filter(Entity2, b: 123)
  end
end
