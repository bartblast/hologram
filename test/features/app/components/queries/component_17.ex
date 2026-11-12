defmodule HologramFeatureTests.Components.Queries.Component17 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Channel
  alias HologramFeatureTests.Entities.Label

  derived :chatty_channels, [Channel], &chatty_channels_query/0
  derived :early_labels, [Label], &early_labels_query/0
  derived :quiet_channels, [Channel], &quiet_channels_query/0

  def template do
    ~HOLO"""
    <p>
      Chatty channels: <strong id="chatty_channels"><code>{names(@chatty_channels)}</code></strong>
    </p>
    <p>
      Quiet channels: <strong id="quiet_channels"><code>{names(@quiet_channels)}</code></strong>
    </p>
    <p>
      Early labels: <strong id="early_labels"><code>{names(@early_labels)}</code></strong>
    </p>
    """
  end

  # The channels with a message past position 2 - a condition on the channel's messages.
  defp chatty_channels_query do
    Channel
    |> filter(any(message <- messages, message.position > 2))
    |> sort(name)
  end

  # The labels whose every message sits before position 3.
  defp early_labels_query do
    Label
    |> filter(all(message <- messages, message.position < 3))
    |> sort(name)
  end

  defp names([]), do: "(none)"

  defp names(rows), do: Enum.map_join(rows, ",", & &1.name)

  # The channels with no message at all.
  defp quiet_channels_query do
    Channel
    |> filter(none(messages))
    |> sort(name)
  end
end
