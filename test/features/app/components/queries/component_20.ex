defmodule HologramFeatureTests.Components.Queries.Component20 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Channel
  alias HologramFeatureTests.Entities.Message

  prop :channels, [Channel], from_query: &channels_query/0
  prop :messages, [Message], from_query: &messages_query/0

  def template do
    ~HOLO"""
    <p>
      Busy channels: <strong id="busy_channels"><code>{channel_counts(@channels)}</code></strong>
    </p>
    <p>
      Recent messages: <strong id="recent_messages"><code>{recent_messages(@channels)}</code></strong>
    </p>
    <p>
      Summaries: <strong id="summaries"><code>{summaries(@messages)}</code></strong>
    </p>
    """
  end

  defp channel_counts(channels) do
    Enum.map_join(channels, ",", &"#{&1.name}:#{&1.message_count}")
  end

  # The channels holding messages, quietest first, with their two latest messages past the drafts
  # and those messages' labels.
  defp channels_query do
    Channel
    |> filter(message_count > 0)
    |> sort(message_count: :asc, name: :asc)
    |> include([message_count, recent_messages.labels])
  end

  defp labels(message) do
    message.labels
    |> Enum.map(& &1.name)
    |> Enum.sort()
    |> Enum.join("+")
  end

  # Every message with what each one reads off its channel.
  defp messages_query do
    Message
    |> sort(position)
    |> include([later_count, summary])
  end

  defp recent_messages(channels) do
    Enum.map_join(channels, ";", fn channel ->
      messages = Enum.map_join(channel.recent_messages, "/", &"#{&1.body}[#{labels(&1)}]")

      "#{channel.name}=#{messages}"
    end)
  end

  defp summaries(messages) do
    Enum.map_join(messages, ",", &"#{&1.summary}:#{&1.later_count}")
  end
end
