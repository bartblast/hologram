defmodule HologramFeatureTests.Entities.Leg do
  use Hologram.Entity

  alias HologramFeatureTests.Entities.Stop

  attribute :name, :string

  relationship :stop, Stop

  # Both rules reach the trip two rows away, through the leg's stop: a leg is added on the trip's
  # update rule, and renamed by an editor of the trip while the trip is not archived.
  allow :create, via: {:update, stop.trip}
  allow :read
  allow :rename, to: {:editor, stop.trip}, when: stop.trip.archived == false
end
