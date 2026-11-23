defmodule HologramFeatureTests.Entities.Waybill do
  use Hologram.Entity

  # Named only by the protocol implementation in waybill_selection.ex, so it syncs only because
  # the browser can run that implementation.
  attribute :code, :string
  attribute :urgent, :boolean, default: false

  allow :read
end
