# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module126 do
  use Hologram.Component
  use Hologram.DB

  import Hologram.Commons.TestUtils, only: [wrap_term: 1]

  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module19
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  derived :rows, [Entity2], fn ->
    helper_module = wrap_term(Module19)

    Entity2
    |> filter(a == true)
    |> helper_module.missing_helper()
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
