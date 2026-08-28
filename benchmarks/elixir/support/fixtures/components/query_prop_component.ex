# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Benchmarks.Fixtures.Components.QueryPropComponent do
  @moduledoc false

  use Hologram.Component
  use Hologram.DB

  alias Hologram.Benchmarks.Fixtures.Entity1

  prop :entities, [Entity1], from_query: &entities_query/1
  prop :min_position, :integer

  def template do
    ~HOLO""
  end

  defp entities_query(min_position) do
    filter(Entity1, position: {:>=, min_position})
  end
end
