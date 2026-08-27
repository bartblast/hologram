defmodule HologramFeatureTests.Components.Queries.Component7 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Ticket

  prop :tickets, [Ticket], from_query: &tickets_query/0
  prop :urgent_tickets, [Ticket], from_query: &urgent_tickets_query/0

  # No init/3, deliberately: the prop is rendered as it resolves. On the server that is the
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
    order_by(Ticket, :priority)
  end

  defp urgent_tickets_query do
    Ticket
    |> filter(priority: {:>=, :medium})
    |> order_by(:title)
  end
end
