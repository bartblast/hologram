# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module4 do
  use Hologram.Entity

  attr :a, :date
  attr :b, :datetime
  attr :c, :enum, values: [:x, :y]
  attr :d, :float
end
