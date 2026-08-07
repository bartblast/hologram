# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module2 do
  use Hologram.Component

  prop :entities, :list, from_query: &__MODULE__.entities_query/1

  @impl Component
  def template do
    ~HOLO""
  end

  def entities_query(_value) do
    nil
  end
end
