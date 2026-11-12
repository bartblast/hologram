# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module80 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :only_ripe, :boolean

  derived :ripe_or_three, [Entity2], fn only_ripe ->
    if only_ripe, do: filter(Entity2, a == true), else: 3
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
