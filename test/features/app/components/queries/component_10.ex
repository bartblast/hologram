defmodule HologramFeatureTests.Components.Queries.Component10 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Product

  prop :products, [Product], from_query: &products_query/0

  # A row's revisions are framework state under __meta__ rather than an attribute, so rendering
  # one proves the whole path carried it: the server struct fills the SSR text, and a change
  # arriving on the stream fills it again from the patch's own revisions, through the client's
  # map and the boxed metadata a template reads.
  def template do
    ~HOLO"""
    <p>
      Revisions: <strong id="product_revisions"><code>{Enum.map_join(@products, ",", &"#{&1.name}:#{&1.__meta__.revisions.name}")}</code></strong>
    </p>
    """
  end

  defp products_query do
    order_by(Product, :name)
  end
end
