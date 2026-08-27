# credo:disable-for-this-file Credo.Check.Readability.Specs
# credo:disable-for-this-file Credo.Check.Refactor.CondStatements
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module16 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :entities, [Entity2], from_query: &entities_query/1

  @impl Component
  def template do
    ~HOLO""
  end

  defp entities_query(min_b) do
    cond do
      min_b -> filter(Entity2, b: {:>=, min_b})
      true -> filter(Entity2, a: true)
    end
  end
end
