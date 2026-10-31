defmodule HologramFeatureTests.Entities.Message do
  use Hologram.Entity

  alias HologramFeatureTests.Entities.Channel
  alias HologramFeatureTests.Entities.Label

  attribute :body, :string
  attribute :position, :integer

  relationship :channel, Channel, optional: true
  relationship :labels, [Label]

  allow :read
end
