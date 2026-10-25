defmodule HologramFeatureTests.Components.Queries.Component15 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Stop

  prop :active_stops, [Stop], from_query: &active_stops_query/0

  def template do
    ~HOLO"""
    <p>
      Active stops: <strong id="active_stops"><code>{Enum.map_join(@active_stops, ",", & &1.name)}</code></strong>
    </p>
    """
  end

  # The stops whose trip is not archived - a condition on the trip each stop belongs to, read
  # through the stop's to-one relationship.
  defp active_stops_query do
    Stop
    |> filter(trip.archived == false)
    |> order_by(name)
  end
end
