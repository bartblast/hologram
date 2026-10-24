defmodule HologramFeatureTests.Components.Policies.Component6 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Stop
  alias HologramFeatureTests.Entities.Trip
  alias HologramFeatureTests.Entities.User

  prop :current_user, User, from_context: {Hologram, :user}
  prop :trips, [Trip], from_query: &trips_query/0

  # Checked while RENDERING, so the check ships to the client and re-answers itself on every
  # render the stream schedules - a grant on a trip arriving changes which trips take a stop.
  # No init/3: both props are rendered as they resolve.
  def template do
    ~HOLO"""
    <p>
      Stoppable: <strong id="stoppable_trips"><code>{Enum.map_join(stoppable(@current_user, @trips), ",", & &1.name)}</code></strong>
    </p>
    """
  end

  defp stoppable(user, trips) do
    Enum.filter(trips, &can?(user, :create, %Stop{trip_id: &1.id}))
  end

  defp trips_query do
    order_by(Trip, name)
  end
end
