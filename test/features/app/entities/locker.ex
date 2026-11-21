defmodule HologramFeatureTests.Entities.Locker do
  use Hologram.Entity

  attribute :open, :boolean, default: false

  # Anybody may create a locker, and nobody may read one, so a browser that creates one holds it
  # only until the server confirms the batch.
  allow :create
end
