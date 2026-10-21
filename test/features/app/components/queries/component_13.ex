defmodule HologramFeatureTests.Components.Queries.Component13 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Ticket

  prop :skipped_title, :string
  prop :tickets, [Ticket], from_query: &tickets_query/1

  def template do
    ~HOLO"""
    <p>
      Alternatives filter: <strong id="alternatives_filter"><code>{Enum.map_join(@tickets, ",", & &1.title)}</code></strong>
    </p>
    """
  end

  # The pinned exclusion sits in the high alternative only, so the low ticket stays whatever its
  # title. The window drops the pinned exclusion and keeps both alternatives - the high one still
  # holds its priority - so a medium ticket is downloaded only when another query asks for it.
  defp tickets_query(skipped_title) do
    Ticket
    |> filter((priority == :high and title != ^skipped_title) or priority == :low)
    |> order_by(title)
  end
end
