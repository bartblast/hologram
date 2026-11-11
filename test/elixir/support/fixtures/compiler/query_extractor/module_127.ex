# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module127 do
  use Hologram.Component
  use Hologram.DB

  import Hologram.Commons.TestUtils, only: [wrap_term: 1]

  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module98
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  derived :rows, [Entity2], fn ->
    Entity2
    |> sort(c)
    |> Module98.narrow(wrap_term(:unknown))
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
