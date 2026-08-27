defmodule HologramFeatureTests.Components.Queries.Component3 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Components.Queries.Component4
  alias HologramFeatureTests.Entities.Product

  prop :products, [Product], from_query: &products_query/0

  # Holds the entity a child queries BY, which is the shape the derived-argument work exists for:
  # one value the parent already has, passed down whole instead of unpacked into a second prop.
  #
  # A query prop resolves against whatever rows exist, so the empty case is a state the page can be
  # in rather than one the test set up wrongly - the child is rendered only when there is an entity
  # to hand it.
  def template do
    ~HOLO"""
    {%if @products != []}<Component4 cid="component_4" product={hd(@products)} />{/if}
    """
  end

  defp products_query do
    order_by(Product, :name)
  end
end
