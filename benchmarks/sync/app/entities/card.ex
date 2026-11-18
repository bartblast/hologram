defmodule HologramSyncBenchmark.Entities.Card do
  use Hologram.Entity

  attribute :position, :integer
  attribute :title, :string

  # A bare rule gives every user the same answer, so every client gets every card and every
  # write to one.
  allow :read
  allow :update
end
