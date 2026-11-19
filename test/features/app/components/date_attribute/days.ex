defmodule HologramFeatureTests.Components.DateAttribute.Days do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Event

  # Ordered by the day itself, and the days shown are the browser's own boxing of what it holds.
  derived :days, [Event], fn ->
    Event
    |> filter(held_on != nil)
    |> sort(held_on)
  end

  def template do
    ~HOLO"""
    <p>
      Days: <strong id="day_order"><code>{Enum.map_join(@days, ",", &to_string(&1.held_on))}</code></strong>
    </p>
    """
  end
end
