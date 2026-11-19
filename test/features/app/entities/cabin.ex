defmodule HologramFeatureTests.Entities.Cabin do
  use Hologram.Entity

  alias HologramFeatureTests.Entities.Ship

  attribute :name, :string

  relationship :ship, Ship

  allow :read
  allow :update, as: :rename, only: [:name], via: {:update, ship}
end
