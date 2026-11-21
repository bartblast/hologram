defmodule HologramFeatureTests.Components.Policies.Component14 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Locker
  alias HologramFeatureTests.Entities.Slip

  derived :lockers, [Locker], &lockers_query/0
  derived :slips, [Slip], &slips_query/0

  def template do
    ~HOLO"""
    <p>
      Slips: <strong id="slips"><code>{Enum.map_join(@slips, ",", & &1.label)}</code></strong>
    </p>
    <p>
      Lockers: <strong id="lockers"><code>{length(@lockers)}</code></strong>
    </p>
    """
  end

  defp lockers_query do
    Locker
  end

  defp slips_query do
    sort(Slip, label)
  end
end
