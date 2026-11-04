# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module61 do
  use Hologram.Component

  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module56
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :min_b, :integer

  prop :entities, [Entity2], from_query: &entities_query/1

  @impl Component
  def template do
    ~HOLO""
  end

  defp entities_query(min_b) do
    # Read through a call, so the compiler does not see the clause no kind matches.
    "closed"
    |> String.to_existing_atom()
    |> Module56.by_kind(min_b)
  end
end
