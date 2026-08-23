defmodule HologramFeatureTests.Entities.Account do
  use Hologram.Entity

  attribute :handle, :string, unique: true

  allow :read
end
