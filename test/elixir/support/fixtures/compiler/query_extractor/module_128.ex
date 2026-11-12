# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module128 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module98
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  derived :ripe_total, :integer, fn ->
    Entity2
    |> filter(a == true)
    |> Module98.keep()
    |> Module98.total()
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
