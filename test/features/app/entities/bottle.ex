defmodule HologramFeatureTests.Entities.Bottle do
  use Hologram.Entity

  alias HologramFeatureTests.Entities.Crate

  attribute :label, :string

  relationship :crate, Crate, optional: true

  # No browser code names this module: the crates page reaches bottles only by the relationship name
  # it includes and reads, so that name is what makes them sync at all.
  allow :read
end

# What the entity impls page prints. An implementation doesn't name the type it's written for, so
# Bottle stays a type browser code reaches only by a relationship name.
defimpl String.Chars, for: HologramFeatureTests.Entities.Bottle do
  def to_string(bottle), do: bottle.label
end
