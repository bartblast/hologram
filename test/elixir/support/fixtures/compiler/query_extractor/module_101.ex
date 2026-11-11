# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module101 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module98
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :wanted, :boolean

  derived :rows, [Entity2], fn wanted -> Module98.drop_ripe(wanted) end

  @impl Component
  def template do
    ~HOLO""
  end
end
