defmodule HologramClusterTests.Components.SyncedItems do
  use Hologram.Component
  use Hologram.DB

  alias HologramClusterTests.Entities.Item

  prop :items, [Item], from_query: &items_query/0

  # The prop exists to give the build a registered query over Item, which is what makes a window
  # for it - the cluster tests read the sync stream directly rather than the rendered page.
  def init(props, component, _server) do
    put_state(component, :items, props.items)
  end

  def template do
    ~HOLO"""
    <p>Items: <strong id="items">{Enum.map_join(@items, ",", & &1.title)}</strong></p>
    """
  end

  defp items_query do
    order_by(Item, :slug)
  end
end
