defprotocol HologramFeatureTests.WaybillSelection do
  def query(selection)
end

defmodule HologramFeatureTests.WaybillSelection.Urgent do
  defstruct []
end

defimpl HologramFeatureTests.WaybillSelection,
  for: HologramFeatureTests.WaybillSelection.Urgent do
  use Hologram.DB

  alias HologramFeatureTests.Entities.Waybill

  def query(_selection) do
    Waybill
    |> filter(urgent == true)
    |> count()
  end
end
