defmodule HologramFeatureTests.Components.Policies.Component8 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Cabin
  alias HologramFeatureTests.Entities.User

  prop :cabins, [Cabin], from_query: &cabins_query/0
  prop :current_user, User, from_context: {Hologram, :user}

  # Checked while RENDERING, so the check ships to the client and answers again on every render
  # the stream schedules. The query includes nothing, and no page queries ships: the ship each
  # cabin's rename rule reads arrives with the cabins because the rule reads it.
  def template do
    ~HOLO"""
    <p>
      Renamable: <strong id="renamable_cabins"><code>{Enum.map_join(renamable(@current_user, @cabins), ",", & &1.name)}</code></strong>
    </p>
    """
  end

  defp cabins_query do
    sort(Cabin, name)
  end

  defp renamable(user, cabins) do
    Enum.filter(cabins, &can?(user, :rename, &1))
  end
end
