defmodule HologramFeatureTests.Components.Derived.Component2 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Ticket

  prop :ticket, Ticket

  # Reads a field of the row it is handed, so a new priority is a new query.
  derived :same_priority, :integer, fn ticket ->
    Ticket
    |> filter(priority == ^ticket.priority)
    |> count()
  end

  # Reads only the row's id, so the row's other fields changing leave the query as it was.
  derived :others, :integer, fn ticket ->
    Ticket
    |> filter(id != ^ticket.id)
    |> count()
  end

  def template do
    ~HOLO"""
    <p>
      Same priority: <strong id="same_priority"><code>{@same_priority}</code></strong>
    </p>
    <p>
      Others: <strong id="others"><code>{@others}</code></strong>
    </p>
    """
  end
end
