defmodule HologramFeatureTests.Components.Queries.Component13 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Ticket

  prop :skipped_title, :string

  derived :tickets, [Ticket], fn skipped_title -> tickets_query(skipped_title) end

  def template do
    ~HOLO"""
    <p>
      Alternatives filter: <strong id="alternatives_filter"><code>{Enum.map_join(@tickets, ",", & &1.title)}</code></strong>
    </p>
    """
  end

  # The pinned exclusion sits in the high alternative only, so the low ticket stays whatever its
  # title, and a medium ticket matches neither alternative.
  defp tickets_query(skipped_title) do
    Ticket
    |> filter((priority == :high and title != ^skipped_title) or priority == :low)
    |> sort(title)
  end
end
