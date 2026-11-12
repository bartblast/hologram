defmodule HologramClusterTests.Components.SyncedItems do
  use Hologram.Component
  use Hologram.DB

  alias HologramClusterTests.Entities.Item

  # The field exists to give the build a registered query over Item, which is what makes a window
  # for it - the cluster tests read the sync stream directly rather than the rendered page.
  derived :items, [Item], &items_query/0

  def template do
    ~HOLO"""
    <p>Items: <strong id="items">{Enum.map_join(@items, ",", & &1.title)}</strong></p>
    """
  end

  defp items_query do
    sort(Item, slug)
  end
end
