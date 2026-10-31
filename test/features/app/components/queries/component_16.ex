defmodule HologramFeatureTests.Components.Queries.Component16 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Channel
  alias HologramFeatureTests.Entities.Label

  prop :channel_name, :string
  prop :channels, [Channel], from_query: &channels_query/1
  prop :label_name, :string
  prop :labels, [Label], from_query: &labels_query/1

  # No page roots a message or a topic, so they reach the client only through the channels' and
  # the labels' inverses.
  def template do
    ~HOLO"""
    <p>
      Channel messages: <strong id="channel_messages"><code>{Enum.map_join(@channels, "; ", &channel_text/1)}</code></strong>
    </p>
    <p>
      Label messages: <strong id="label_messages"><code>{Enum.map_join(@labels, "; ", &label_text/1)}</code></strong>
    </p>
    """
  end

  defp bodies([]), do: "(none)"

  defp bodies(messages), do: Enum.map_join(messages, ", ", & &1.body)

  defp channel_text(channel) do
    case channel.topic do
      nil -> "#{channel.name}: #{bodies(channel.messages)}"
      topic -> "#{channel.name}: #{bodies(channel.messages)} | topic: #{topic.title}"
    end
  end

  # The name is pinned, so the window downloads every channel with its messages and topic while
  # the render reads one.
  defp channels_query(channel_name) do
    Channel
    |> filter(name == ^channel_name)
    |> include([messages, topic])
  end

  # A label's messages declare no order, so the text puts them in one.
  defp label_text(label) do
    messages = Enum.sort_by(label.messages, & &1.body)

    "#{label.name}: #{bodies(messages)}"
  end

  defp labels_query(label_name) do
    Label
    |> filter(name == ^label_name)
    |> include(messages)
  end
end
