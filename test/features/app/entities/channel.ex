defmodule HologramFeatureTests.Entities.Channel do
  use Hologram.Entity

  alias HologramFeatureTests.Entities.Message
  alias HologramFeatureTests.Entities.Topic

  attribute :name, :string

  relationship :messages, [Message], inverse: channel, sort: position
  relationship :topic, Topic, inverse: channel

  allow :read
end
