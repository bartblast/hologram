# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module4 do
  use Hologram.Entity

  attribute :a, :date
  attribute :b, :datetime
  attribute :c, :enum, values: [:x, :y], default: :x
  attribute :d, :float
end
