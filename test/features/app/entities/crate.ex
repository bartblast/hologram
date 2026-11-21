defmodule HologramFeatureTests.Entities.Crate do
  use Hologram.Entity

  alias HologramFeatureTests.Entities.Bottle

  attribute :name, :string

  relationship :bottles, [Bottle], inverse: crate, sort: label

  allow :read
end
