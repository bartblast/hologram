defmodule HologramFeatureTests.Components.Queries.Component3 do
  use Hologram.Component
  use Hologram.Query

  alias HologramFeatureTests.Components.Queries.Component4
  alias HologramFeatureTests.Entities.Product

  prop :products, [Product], from_query: &products_query/0

  # Holds the entity a child queries BY, which is the shape the derived-argument work exists for:
  # one value the parent already has, passed down whole instead of unpacked into a second prop.
  def template do
    ~HOLO"""
    <Component4 cid="component_4" product={hd(@products)} />
    """
  end

  defp products_query do
    order_by(Product, :name)
  end
end
