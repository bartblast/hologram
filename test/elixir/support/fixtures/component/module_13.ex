# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Component.Module13 do
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  def bounded_query(nil) do
    filter(Entity2, a: true)
  end

  def bounded_query(min_b) do
    filter(Entity2, b: {:>=, min_b})
  end
end
