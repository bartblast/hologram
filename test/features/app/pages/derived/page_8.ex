defmodule HologramFeatureTests.Derived.Page8 do
  use Hologram.Page
  use Hologram.DB

  alias Hologram.UI.Link
  alias HologramFeatureTests.Derived.Page3
  alias HologramFeatureTests.Entities.Ticket

  route "/derived/8"

  layout HologramFeatureTests.Components.DefaultLayout

  # A count that reads no row of the page, so it renders over a browser holding no tickets at all.
  derived :total, :integer, fn ->
    count(Ticket)
  end

  def template do
    ~HOLO"""
    <p>
      Total: <strong id="total"><code>{@total}</code></strong>
    </p>
    <p>
      <Link to={Page3}>Away link</Link>
    </p>
    """
  end
end
