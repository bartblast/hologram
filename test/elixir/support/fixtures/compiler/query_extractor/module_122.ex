# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module122 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module3, as: Entity3

  prop :since, :datetime

  derived :rows, [Entity3], fn since ->
    Enum.reduce([:a], Entity3, fn name, query ->
      if since do
        filter(query, created_at >= ^since)
      else
        include(query, ^name)
      end
    end)
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
