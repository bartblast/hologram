# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module32 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :n, :integer
  prop :entities, [Entity2], from_query: &entities_query/1

  @impl Component
  def template do
    ~HOLO""
  end

  defp entities_query(n) do
    filter(Entity2, b: n * 2)
  end
end
