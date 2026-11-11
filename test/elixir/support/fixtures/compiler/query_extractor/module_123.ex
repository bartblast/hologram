# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module123 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module56
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :min_b, :integer

  derived :rows, [Entity2], fn min_b ->
    # Read through a call, so the compiler does not see the clause no kind matches.
    kind = String.to_existing_atom("closed")

    Module56.case_kind(min_b, kind)
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
