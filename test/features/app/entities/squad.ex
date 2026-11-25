defmodule HologramFeatureTests.Entities.Squad do
  use Hologram.Entity

  alias HologramFeatureTests.Entities.Errand

  attribute :name, :string

  relationship :errands, [Errand], inverse: squad

  role :member

  allow :read
end
