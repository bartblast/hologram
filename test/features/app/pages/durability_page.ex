defmodule HologramFeatureTests.DurabilityPage do
  use Hologram.Page

  alias HologramFeatureTests.Components.Queries.Component2

  route "/durability"

  layout HologramFeatureTests.Components.DefaultLayout

  # Nothing is read until the button is clicked, so this page CARRIES no rows - the server renders
  # it without touching the products, and none of them travel with the markup. Whatever the list
  # shows afterwards therefore came from the client's own database: filled by the stream on a first
  # visit, and read back from durable storage on every visit after that.
  def init(_params, component, _server) do
    put_state(component, :show_products, false)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="show_products">Show products</button>
    </p>
    {%if @show_products}
      <Component2 />
    {/if}
    """
  end

  def action(:show_products, _params, component) do
    put_state(component, :show_products, true)
  end
end
