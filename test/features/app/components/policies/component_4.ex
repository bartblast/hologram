defmodule HologramFeatureTests.Components.Policies.Component4 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Booking
  alias HologramFeatureTests.Entities.User

  prop :bookings, [Booking], from_query: &bookings_query/0
  prop :current_user, User, from_context: {Hologram, :user}

  # Checked while RENDERING, so the check ships to the client and answers there as well. No
  # init/3: both props are rendered as they resolve.
  def template do
    ~HOLO"""
    <p>
      Bookings: <strong id="bookings"><code>{Enum.map_join(@bookings, ",", & &1.name)}</code></strong>
    </p>
    <p>
      Confirmable: <strong id="confirmable_bookings"><code>{Enum.map_join(confirmable(@current_user, @bookings), ",", & &1.name)}</code></strong>
    </p>
    """
  end

  defp bookings_query do
    order_by(Booking, name)
  end

  defp confirmable(user, bookings) do
    Enum.filter(bookings, &can?(user, :confirm, &1))
  end
end
