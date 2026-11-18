defmodule HologramFeatureTests.Derived.Page4 do
  use Hologram.Page
  use Hologram.DB

  alias HologramFeatureTests.Components.Derived.Component2
  alias HologramFeatureTests.Entities.Ticket

  route "/derived/4"

  layout HologramFeatureTests.Components.DefaultLayout

  derived :ticket, Ticket, fn ->
    Ticket
    |> filter(title == "alpha")
    |> one()
  end

  # The ticket is lowered in the BROWSER, so the component it is handed to counts for its new
  # priority before the server's echo of the write arrives.
  def template do
    ~HOLO"""
    <p>
      <button $click={action: :lower_alpha}> Lower alpha </button>
    </p>
    <Component2 cid="ticket_counts" ticket={@ticket} />
    """
  end

  def action(:lower_alpha, _params, component) do
    component.derived.ticket
    |> put_attribute(:priority, :low)
    |> DB.update!()

    component
  end
end
