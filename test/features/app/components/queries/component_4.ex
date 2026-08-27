defmodule HologramFeatureTests.Components.Queries.Component4 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Product
  alias HologramFeatureTests.Entities.Review

  prop :product, Product
  prop :reviews, [Review], from_query: &reviews_query/1

  def template do
    ~HOLO"""
    <p>
      Field read: <strong id="field_read"><code>{Enum.map_join(@reviews, ",", & &1.body)}</code></strong>
    </p>
    """
  end

  # Reads a field off the argument rather than taking a second, like-named prop for it.
  defp reviews_query(product) do
    Review
    |> filter(product_id: product.id)
    |> order_by(:rating)
  end
end
