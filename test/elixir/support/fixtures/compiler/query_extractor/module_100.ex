# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module100 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module98

  derived :pair, :tuple, fn -> {Module98.ripe(), 1} end

  @impl Component
  def template do
    ~HOLO""
  end
end
