# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module90 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module98
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  derived :ripe_total, :integer, fn ->
    Entity2
    |> filter(a == true)
    |> Module98.keep()
    |> length()
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
