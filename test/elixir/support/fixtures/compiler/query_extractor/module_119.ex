# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module119 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :min_b, :integer

  derived :rows, [Entity2], fn min_b -> rows_query(min_b) end

  @impl Component
  def template do
    ~HOLO""
  end

  defp rows_query(0), do: Entity2

  defp rows_query(min_b) do
    (min_b - 1)
    |> rows_query()
    |> filter(b >= ^min_b)
  end
end
