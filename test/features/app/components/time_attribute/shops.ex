defmodule HologramFeatureTests.Components.TimeAttribute.Shops do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Shop

  # Ordered by the time itself, so where a shop with no opening hour lands is something the DOM
  # says rather than something a scenario has to take on faith.
  prop :shops, [Shop], from_query: &shops_query/0

  def template do
    ~HOLO"""
    <ul id="shops">
      {%for shop <- @shops}
        <li>{shop.name} {shop.opens_at} {shop.closes_at}</li>
      {/for}
    </ul>
    <p>
      Order: <strong id="shop_order"><code>{Enum.map_join(@shops, ",", & &1.name)}</code></strong>
    </p>
    """
  end

  defp shops_query do
    order_by(Shop, :opens_at)
  end
end
