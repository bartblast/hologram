defmodule HologramFeatureTests.Entities.Membership do
  use Hologram.Entity

  alias HologramFeatureTests.Entities.Channel

  attribute :seen_position, :integer

  relationship :channel, Channel

  allow :read
end
