defmodule HologramClusterTests.SyncPage do
  use Hologram.Page

  alias HologramClusterTests.Components.SyncedItems

  route "/sync"

  layout HologramClusterTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <SyncedItems cid="synced_items" />
    """
  end
end
