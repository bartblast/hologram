# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module82 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  derived :rows, [Entity2], fn -> Entity2 end

  derived :ripe_rows, [Entity2], fn rows -> filter(rows, a == true) end

  @impl Component
  def template do
    ~HOLO""
  end
end
