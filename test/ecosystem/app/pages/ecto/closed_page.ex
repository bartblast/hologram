# Puts an Ecto schema into state, and no client code calls a reflection function on it: the page's
# bundle must get none of them. Client-reachable code on this page must not name the schema.
defmodule HologramEcosystemTests.Ecto.ClosedPage do
  use Hologram.Page

  alias HologramEcosystemTests.Ecto.Tag

  route "/ecto/closed"

  layout HologramEcosystemTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :schema, Tag)
  end

  def template do
    ~HOLO"""
    <p id="text">Closed</p>
    """
  end
end
