defmodule HologramFeatureTests.Entities.Bottle do
  use Hologram.Entity

  alias HologramFeatureTests.Entities.Crate

  attribute :label, :string

  relationship :crate, Crate, optional: true

  # No browser code names this module: the crates page reaches bottles only by the relationship name
  # it includes and reads, so that name is what makes them sync at all.
  allow :read
end
