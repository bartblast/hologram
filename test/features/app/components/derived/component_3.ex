defmodule HologramFeatureTests.Components.Derived.Component3 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Ticket

  prop :excluded_titles, :any

  # The query is built one stage per excluded title, folded over the list the prop holds.
  derived :reduced, [Ticket], fn excluded_titles ->
    excluded_titles
    |> Enum.reduce(Ticket, fn excluded, query -> filter(query, title != ^excluded) end)
    |> sort(title)
  end

  # The same query, built by a helper calling itself once per excluded title.
  derived :recursed, [Ticket], fn excluded_titles ->
    Ticket
    |> excluding(excluded_titles)
    |> sort(title)
  end

  def template do
    ~HOLO"""
    <p>
      Reduced: <strong id="reduced"><code>{Enum.map_join(@reduced, ",", & &1.title)}</code></strong>
    </p>
    <p>
      Recursed: <strong id="recursed"><code>{Enum.map_join(@recursed, ",", & &1.title)}</code></strong>
    </p>
    """
  end

  defp excluding(query, []), do: query

  defp excluding(query, [excluded | rest]) do
    query
    |> filter(title != ^excluded)
    |> excluding(rest)
  end
end
