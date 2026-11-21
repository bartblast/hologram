defmodule HologramFeatureTests.Components.Derived.Component4 do
  use Hologram.Component

  alias HologramFeatureTests.Entities.Ticket

  prop :query, :any

  # The rows of the query it is handed, whoever built it.
  derived :tickets, [Ticket], fn query -> query end

  def template do
    ~HOLO"""
    <p>
      Handed tickets: <strong id="handed_tickets"><code>{Enum.map_join(@tickets, ",", & &1.title)}</code></strong>
    </p>
    """
  end
end
