# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module102 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :flags, :list

  derived :rows, [Entity2], fn flags ->
    Enum.reduce(flags, sort(Entity2, c), fn flag, query -> filter(query, a == ^flag) end)
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
