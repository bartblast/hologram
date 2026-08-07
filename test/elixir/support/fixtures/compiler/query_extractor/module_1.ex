# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module1 do
  use Hologram.Component
  use Hologram.Query

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :count, :integer
  prop :entities, [Entity2], from_query: &__MODULE__.entities_query/0

  @impl Component
  def template do
    ~HOLO""
  end

  def entities_query do
    Entity2
    |> filter(a: true)
    |> order_by(:c)
  end
end
