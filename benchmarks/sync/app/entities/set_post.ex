defmodule HologramSyncBenchmark.Entities.SetPost do
  use Hologram.Entity

  alias HologramSyncBenchmark.Entities.SetTag

  attribute :position, :integer
  attribute :title, :string
  attribute :visible, :boolean, default: false

  relationship :tags, [SetTag]

  # Only a few posts are visible, so the clients stay small while the one tag's set is huge: what
  # the big set case measures is the server reading that set, not clients downloading it.
  allow :read, when: visible == true
  allow :update
end
