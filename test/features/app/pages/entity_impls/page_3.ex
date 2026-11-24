defmodule HologramFeatureTests.EntityImpls.Page3 do
  use Hologram.Page
  use Hologram.DB

  alias HologramFeatureTests.Entities.Event

  route "/entity-impls/3"

  layout HologramFeatureTests.Components.DefaultLayout

  derived :events, [Event], fn -> sort(Event, name) end

  # Names neither Date nor DateTime: the browser builds them for the row's fields.
  def template do
    ~HOLO"""
    <p>
      Events: <strong id="events"><code>{Enum.map_join(@events, ",", fn event -> "#{event.name}|#{event.held_on}|#{event.created_at}" end)}</code></strong>
    </p>
    """
  end
end
