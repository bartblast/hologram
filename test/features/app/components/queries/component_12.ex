defmodule HologramFeatureTests.Components.Queries.Component12 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Ticket

  prop :page, :integer
  prop :size, :integer
  prop :sort_by, :atom
  prop :tickets, [Ticket], from_query: &tickets_query/3

  def template do
    ~HOLO"""
    <p>
      Pinned pagination: <strong id="pinned_pagination"><code>{Enum.map_join(@tickets, ",", & &1.title)}</code></strong>
    </p>
    """
  end

  # The ordering key and both page options arrive as props, so each is pinned.
  defp tickets_query(page, size, sort_by) do
    Ticket
    |> order_by(^[{sort_by, :asc}])
    |> paginate(page: ^page, size: ^size)
  end
end
