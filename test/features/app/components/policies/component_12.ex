defmodule HologramFeatureTests.Components.Policies.Component12 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Parcel
  alias HologramFeatureTests.Entities.User

  prop :current_user, User, from_context: {Hologram, :user}

  derived :parcels, [Parcel], &parcels_query/0

  # Checked while rendering, so each check ships to the browser and is answered again on every
  # render the stream schedules. Each read rule reads a vault or a shelf, which no browser holds,
  # so the browser answers it from the server's verdict on the parcel.
  def template do
    ~HOLO"""
    <p>
      Parcels: <strong id="parcels"><code>{Enum.map_join(@parcels, ",", & &1.label)}</code></strong>
    </p>
    <p>
      Readable parcels: <strong id="readable_parcels"><code>{Enum.map_join(Enum.filter(@parcels, &can?(@current_user, :read, &1)), ",", & &1.label)}</code></strong>
    </p>
    """
  end

  defp parcels_query do
    sort(Parcel, label)
  end
end
