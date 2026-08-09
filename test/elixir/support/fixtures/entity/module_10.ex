# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module10 do
  use Hologram.Entity

  attribute :count, :integer, min: 1, max: 10
  attribute :held_at, :datetime, min: ~U[2026-01-01 00:00:00Z], optional: true
  attribute :rating, :float, min: 0, max: 5.0, optional: true
  attribute :released_on, :date, max: ~D[2030-12-31], optional: true
end
