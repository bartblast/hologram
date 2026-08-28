# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module22 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module3, as: Entity3

  prop :entities, [Entity3], from_query: &entities_query/1

  @impl Component
  def template do
    ~HOLO""
  end

  defp entities_query(min_b) do
    include(Entity3, :a, fn sub ->
      if min_b do
        filter(sub, b: {:>=, min_b})
      else
        sub
      end
    end)
  end
end
