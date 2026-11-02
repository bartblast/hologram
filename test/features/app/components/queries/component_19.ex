defmodule HologramFeatureTests.Components.Queries.Component19 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Ticket

  prop :exact_tickets, [Ticket], from_query: &exact_tickets_query/1
  prop :query, :string
  prop :tickets, [Ticket], from_query: &tickets_query/1

  def template do
    ~HOLO"""
    <p>
      Loose search: <strong id="loose_search"><code>{titles(@tickets)}</code></strong>
    </p>
    <p>
      Exact search: <strong id="exact_search"><code>{titles(@exact_tickets)}</code></strong>
    </p>
    """
  end

  defp titles([]), do: "(none)"

  defp titles(tickets), do: Enum.map_join(tickets, ",", & &1.title)

  # The titles starting with the typed term byte for byte.
  defp exact_tickets_query(query) do
    Ticket
    |> filter(starts_with(title, ^query, match: :exact))
    |> sort(title)
  end

  # A typeahead: the titles starting with the typed term, case and accents ignored.
  defp tickets_query(query) do
    Ticket
    |> filter(starts_with(title, ^query))
    |> sort(title)
  end
end
