# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module18 do
  use Hologram.Component

  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module19
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :entities, [Entity2], from_query: &entities_query/1

  @impl Component
  def template do
    ~HOLO""
  end

  defp entities_query(min_b) do
    Module19.bounded_query(min_b)
  end
end
