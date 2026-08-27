defmodule HologramFeatureTests.Components.Mutations.Items do
  use Hologram.Component
  use Hologram.Query

  alias HologramFeatureTests.Entities.Item

  # The items reach this list through the ordinary read path - a registered query filled by the
  # sync stream - so a counter moved by a batch POSTed from the page shows its new value here
  # without the page being fetched again.
  prop :items, [Item], from_query: &items_query/0

  def template do
    ~HOLO"""
    <ul id="items">
      {%for item <- @items}
        <li>{item.name}: {item.stock}</li>
      {/for}
    </ul>
    """
  end

  defp items_query do
    order_by(Item, :name)
  end
end
