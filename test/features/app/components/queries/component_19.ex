defmodule HologramFeatureTests.Components.Queries.Component19 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Ticket

  prop :query, :string

  derived :exact_tickets, [Ticket], fn query -> exact_tickets_query(query) end
  derived :tickets, [Ticket], fn query -> tickets_query(query) end

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
    |> filter(starts_with(title, ^query, mode: :exact))
    |> sort(title)
  end

  # A typeahead: the titles starting with the typed term, case and accents ignored.
  defp tickets_query(query) do
    Ticket
    |> filter(starts_with(title, ^query))
    |> sort(title)
  end
end
