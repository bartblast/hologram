defmodule HologramFeatureTests.Entities.Product do
  use Hologram.Entity

  attribute :name, :string

  allow :read
end
