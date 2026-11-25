defmodule HologramFeatureTests.Derived.Page8 do
  use Hologram.Page

  alias HologramFeatureTests.WaybillSelection
  alias HologramFeatureTests.WaybillSelection.Urgent

  route "/derived/8"

  layout HologramFeatureTests.Components.DefaultLayout

  # The query comes from a protocol implementation, the only browser code naming its entity type.
  # A count is declared :integer, so the declaration doesn't name the type either.
  derived :urgent_count, :integer, fn -> WaybillSelection.query(%Urgent{}) end

  def template do
    ~HOLO"""
    <p>
      Urgent waybills: <strong id="urgent_count"><code>{@urgent_count}</code></strong>
    </p>
    """
  end
end
