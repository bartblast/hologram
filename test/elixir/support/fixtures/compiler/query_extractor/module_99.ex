# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module99 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  derived :labels, :list, fn ->
    Entity2
    |> filter(a == true)
    |> Enum.map(& &1.c)
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
