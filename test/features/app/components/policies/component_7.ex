defmodule HologramFeatureTests.Components.Policies.Component7 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Leg
  alias HologramFeatureTests.Entities.Stop
  alias HologramFeatureTests.Entities.User

  prop :current_user, User, from_context: {Hologram, :user}
  prop :legs, [Leg], from_query: &legs_query/0
  prop :stops, [Stop], from_query: &stops_query/0

  # Checked while RENDERING, so the checks ship to the client and re-answer themselves on every
  # render the stream schedules - a grant on a trip arriving changes which stops take a leg and
  # which legs may be renamed. No init/3: the props are rendered as they resolve.
  def template do
    ~HOLO"""
    <p>
      Leggable: <strong id="leggable_stops"><code>{Enum.map_join(leggable(@current_user, @stops), ",", & &1.name)}</code></strong>
    </p>
    <p>
      Renamable: <strong id="renamable_legs"><code>{Enum.map_join(renamable(@current_user, @legs), ",", & &1.name)}</code></strong>
    </p>
    """
  end

  defp leggable(user, stops) do
    Enum.filter(stops, &can?(user, :create, %Leg{stop_id: &1.id}))
  end

  defp legs_query do
    order_by(Leg, name)
  end

  defp renamable(user, legs) do
    Enum.filter(legs, &can?(user, :rename, &1))
  end

  defp stops_query do
    order_by(Stop, name)
  end
end
