defmodule HologramFeatureTests.Entities.Topic do
  use Hologram.Entity

  alias HologramFeatureTests.Entities.Channel

  attribute :title, :string

  relationship :channel, Channel, unique: true

  allow :read
end
