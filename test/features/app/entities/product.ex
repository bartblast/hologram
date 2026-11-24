defmodule HologramFeatureTests.Entities.Product do
  use Hologram.Entity

  attribute :name, :string

  allow :delete
  allow :read
end
