defmodule HologramFeatureTests.Entities.Binder do
  use Hologram.Entity

  alias HologramFeatureTests.Entities.Decal

  attribute :name, :string
  attribute :note, :string

  relationship :decals, [Decal]

  allow :read
  allow :update
end
