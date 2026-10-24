defmodule HologramFeatureTests.Entities.Stop do
  use Hologram.Entity

  alias HologramFeatureTests.Entities.Trip

  attribute :name, :string

  relationship :trip, Trip

  allow :create, via: {:update, trip}
  allow :read
end
