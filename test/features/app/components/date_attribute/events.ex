defmodule HologramFeatureTests.Components.DateAttribute.Events do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Event

  prop :since, DateTime

  # Filtered by an instant the page writes in another zone, so the events listed are the ones the
  # browser takes it to mean.
  derived :events, [Event], fn since ->
    Event
    |> filter(starts_at >= ^since)
    |> sort(starts_at)
  end

  def template do
    ~HOLO"""
    <p>
      Since: <strong id="event_order"><code>{Enum.map_join(@events, ",", & &1.name)}</code></strong>
    </p>
    """
  end
end
