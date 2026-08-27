defmodule HologramFeatureTests.Entities.Item do
  use Hologram.Entity

  attribute :name, :string
  attribute :stock, :integer, default: 0, min: 0

  allow :read
  allow :update
end
