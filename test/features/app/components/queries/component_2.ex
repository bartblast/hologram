defmodule HologramFeatureTests.Components.Queries.Component2 do
  use Hologram.Component
  use Hologram.Query

  alias HologramFeatureTests.Entities.Product

  prop :products, [Product], from_query: &products_query/0

  # No init/3, deliberately: the prop is rendered as it resolves. On the server that is the
  # query against Postgres, and on the client the same query against the client's own database -
  # which is what makes a change arriving on the stream reach this DOM without anyone asking.
  def template do
    ~HOLO"""
    <p>
      Products: <strong id="live_products"><code>{Enum.map_join(@products, ",", & &1.name)}</code></strong>
    </p>
    """
  end

  defp products_query do
    order_by(Product, :name)
  end
end
