defmodule HologramFeatureTests.Components.Queries.Component11 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Ticket

  prop :min_priority, :atom
  prop :page_size, :integer
  prop :skipped_title, :string
  prop :tickets, [Ticket], from_query: &tickets_query/3

  def template do
    ~HOLO"""
    <p>
      Expression filter: <strong id="expression_filter"><code>{Enum.map_join(@tickets, ",", & &1.title)}</code></strong>
    </p>
    """
  end

  # Every outside value is pinned and every literal is written out, in each position a query takes
  # one: a comparison, a negated membership, a direction and a bound.
  defp tickets_query(min_priority, skipped_title, page_size) do
    Ticket
    |> filter(priority >= ^min_priority and title != ^skipped_title)
    |> filter(title not in ["zz"])
    |> order_by(priority: :desc, title: :asc)
    |> limit(^page_size)
  end
end
