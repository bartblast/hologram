# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module138 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :kind, :atom
  prop :search, :string

  derived :rows, [Entity2], fn kind, search ->
    filter(kind, nonexistent == search and c != ^search)
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
