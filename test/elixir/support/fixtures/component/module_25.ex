# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Component.Module25 do
  use Hologram.Component
  use Hologram.Query

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :entities, [Entity2], from_query: &entities_query/1
  prop :max_b, :integer
  prop :min_b, :integer

  @impl Component
  def template do
    ~HOLO""
  end

  # The clauses name one argument position differently, so which prop feeds it has no answer.
  defp entities_query(min_b) when is_integer(min_b) do
    filter(Entity2, b: {:>=, min_b})
  end

  defp entities_query(max_b) do
    filter(Entity2, b: {:<=, max_b})
  end
end
