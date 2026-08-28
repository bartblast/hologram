defmodule HologramFeatureTests.Components.Queries.Component1 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Product

  prop :products, [Product], from_query: &products_query/0

  # The query result arrives as a server-injected prop and hydrates the client
  # through state - client-side from_query rendering runs on the local database,
  # which is not built yet.
  def init(props, component, _server) do
    put_state(component, :products, props.products)
  end

  def template do
    ~HOLO"""
    <p>
      Products: <strong id="products"><code>{Enum.map_join(@products, ",", & &1.name)}</code></strong>
    </p>
    """
  end

  defp products_query do
    order_by(Product, :name)
  end
end
