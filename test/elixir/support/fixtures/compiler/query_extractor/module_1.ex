# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module1 do
  use Hologram.Component

  alias Hologram.Query
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :count, :integer
  prop :entities, :list, from_query: &__MODULE__.entities_query/0

  @impl Component
  def template do
    ~HOLO""
  end

  def entities_query do
    Entity2
    |> Query.filter(a: true)
    |> Query.order_by(:c)
  end
end
