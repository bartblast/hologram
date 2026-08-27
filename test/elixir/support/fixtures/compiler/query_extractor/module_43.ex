# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module43 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :entities, [Entity2], from_query: &entities_query/1

  @impl Component
  def template do
    ~HOLO""
  end

  defp entities_query(min_b) do
    Entity2
    |> filter(b: {:>=, min_b})
    |> narrow()
  end

  defp narrow(query) do
    filter(query, nonexistent: 1)
  end
end
