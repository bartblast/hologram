# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module72 do
  use Hologram.Component

  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module56
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :kind, :atom
  prop :min_b, :integer

  prop :entities, [Entity2], from_query: &entities_query/2

  @impl Component
  def template do
    ~HOLO""
  end

  defp entities_query(min_b, kind) do
    Module56.paired(min_b, kind)
  end
end
