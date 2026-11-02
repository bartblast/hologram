defmodule HologramFeatureTests.Queries.Page11 do
  use Hologram.Page

  alias HologramFeatureTests.Components.Queries.Component19

  route "/queries/11"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :query, "JOSE")
  end

  def template do
    ~HOLO"""
    <Component19 cid="component_19" query={@query} />
    <p>
      <button $click="search_for_zoe">Search for zoe</button>
    </p>
    """
  end

  def action(:search_for_zoe, _params, component) do
    put_state(component, :query, "zoe")
  end
end
