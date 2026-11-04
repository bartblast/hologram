defmodule HologramFeatureTests.Entities.Message do
  use Hologram.Entity

  alias HologramFeatureTests.Entities.Channel
  alias HologramFeatureTests.Entities.Label
  alias HologramFeatureTests.Queries

  attribute :body, :string
  attribute :position, :integer

  relationship :channel, Channel, optional: true
  relationship :labels, [Label]

  derived :later_count, :integer, fn channel, position ->
    Queries.later_count(channel, position)
  end

  derived :summary, :string, fn body, channel -> body <> " in " <> channel.name end

  allow :read
end
