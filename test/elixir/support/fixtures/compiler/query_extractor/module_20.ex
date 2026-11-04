# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module20 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module3, as: Entity3

  prop :entities, [Entity3], from_query: &entities_query/1

  @impl Component
  def template do
    ~HOLO""
  end

  defp entities_query(since) do
    Enum.reduce([:a], Entity3, fn name, query ->
      query
      |> include(^name)
      |> filter(created_at >= ^since)
    end)
  end
end
