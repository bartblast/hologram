# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Component.Module55 do
  # A query builder a derived field calls.

  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  def bounded(min_b), do: filter(Entity2, b >= ^min_b)
end
