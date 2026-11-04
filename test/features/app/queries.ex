defmodule HologramFeatureTests.Queries do
  # The query builders the entities' derived fields call.

  import Hologram.Query

  def later_count(channel, position) do
    channel.messages
    |> filter(position > ^position)
    |> count()
  end
end
