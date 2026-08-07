# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module3 do
  use Hologram.Component

  prop :entities, :list, from_query: 123

  @impl Component
  def template do
    ~HOLO""
  end
end
