defmodule HologramFeatureTests.Entities.Jar do
  use Hologram.Entity

  alias HologramFeatureTests.Entities.Pantry

  # The row type whose implementation of PantryReport names Lid.
  attribute :label, :string

  relationship :pantry, Pantry, optional: true

  allow :read
end
