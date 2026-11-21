defmodule HologramFeatureTests.Derived.Page6 do
  use Hologram.Page
  use Hologram.DB

  alias HologramFeatureTests.Components.Derived.Component4
  alias HologramFeatureTests.Entities.Ticket

  route "/derived/6"

  layout HologramFeatureTests.Components.DefaultLayout

  state :query, :any

  # Built on the server and carried to the browser in the page's state, where the component's
  # derived field runs it again over the browser's own database.
  def init(_params, component, _server) do
    query =
      Ticket
      |> filter(priority == :high)
      |> sort(title)

    put_state(component, :query, query)
  end

  def template do
    ~HOLO"""
    <Component4 cid="handed_query" query={@query} />
    """
  end
end
