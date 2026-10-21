defmodule HologramFeatureTests.Components.Queries.Component14 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Booking

  prop :bookings, [Booking], from_query: &bookings_query/0
  prop :reversed_bookings, [Booking], from_query: &reversed_bookings_query/0

  def template do
    ~HOLO"""
    <p>
      Bookings: <strong id="bookings"><code>{Enum.map_join(@bookings, ",", & &1.name)}</code></strong>
    </p>
    <p>
      Reversed bookings: <strong id="reversed_bookings"><code>{Enum.map_join(@reversed_bookings, ",", & &1.name)}</code></strong>
    </p>
    """
  end

  # Every booking, so the page's local read answers from the whole set.
  defp bookings_query do
    order_by(Booking, name)
  end

  defp reversed_bookings_query do
    Booking
    |> filter(check_out < check_in)
    |> order_by(name)
  end
end
