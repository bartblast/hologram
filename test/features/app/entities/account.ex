defmodule HologramFeatureTests.Entities.Account do
  use Hologram.Entity

  attribute :bio, :string, max_length: 10, optional: true
  attribute :handle, :string, unique: true

  allow :read
end
