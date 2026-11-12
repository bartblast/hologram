defmodule HologramFeatureTests.Components.Queries.Component7 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Ticket

  derived :tickets, [Ticket], &tickets_query/0
  derived :urgent_tickets, [Ticket], &urgent_tickets_query/0

  # No init/3, deliberately: the derived fields are rendered as they resolve. On the server that is
  # the
  # query against Postgres, and on the client the same query against the client's own database -
  # which is what makes a change arriving on the stream reach this DOM without anyone asking.
  def template do
    ~HOLO"""
    <p>
      Tickets: <strong id="tickets"><code>{Enum.map_join(@tickets, ",", & &1.title)}</code></strong>
    </p>
    <p>
      Urgent: <strong id="urgent_tickets"><code>{Enum.map_join(@urgent_tickets, ",", & &1.title)}</code></strong>
    </p>
    """
  end

  defp tickets_query do
    sort(Ticket, priority)
  end

  defp urgent_tickets_query do
    Ticket
    |> filter(priority >= :medium)
    |> sort(title)
  end
end
