defmodule HologramFeatureTests.Derived.Page2 do
  use Hologram.Page
  use Hologram.DB

  alias HologramFeatureTests.Entities.Ticket

  route "/derived/2/:title"

  param :title, :string

  layout HologramFeatureTests.Components.DefaultLayout

  derived :tickets, [Ticket], fn title -> filter(Ticket, title == ^title) end

  def template do
    ~HOLO"""
    <p>
      Page tickets: <strong id="page_tickets"><code>{Enum.map_join(@tickets, ",", &"#{&1.title}:#{&1.priority}")}</code></strong>
    </p>
    """
  end
end
