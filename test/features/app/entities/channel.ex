defmodule HologramFeatureTests.Entities.Channel do
  use Hologram.Entity

  alias HologramFeatureTests.Entities.Message
  alias HologramFeatureTests.Entities.Topic

  attribute :name, :string

  relationship :messages, [Message], inverse: channel, sort: position
  relationship :topic, Topic, inverse: channel

  derived :message_count, :integer, fn messages -> count(messages) end

  derived :recent_messages, [Message], fn messages ->
    messages
    |> filter(position > 0)
    |> sort(position: :desc)
    |> take(2)
    |> include(labels)
  end

  allow :read
end
