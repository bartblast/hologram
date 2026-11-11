# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module110 do
  use Hologram.Component
  use Hologram.DB

  import Hologram.Commons.TestUtils, only: [wrap_term: 1]

  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module19
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :min_b, :integer

  derived :rows, [Entity2], fn min_b ->
    helper_module = wrap_term(Module19)

    min_b
    |> helper_module.missing_helper()
    |> filter(a: true)
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
