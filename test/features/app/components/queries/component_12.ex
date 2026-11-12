defmodule HologramFeatureTests.Components.Queries.Component12 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Ticket

  prop :page, :integer
  prop :size, :integer
  prop :sort_by, :atom

  derived :tickets, [Ticket], fn page, size, sort_by -> tickets_query(page, size, sort_by) end

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
    |> sort(^[{sort_by, :asc}])
    |> paginate(page: ^page, size: ^size)
  end
end
