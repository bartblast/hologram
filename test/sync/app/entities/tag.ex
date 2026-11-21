defmodule HologramSyncTests.Entities.Tag do
  use Hologram.Entity

  alias HologramSyncTests.Entities.Card

  attribute :name, :string

  relationship :cards, [Card], inverse: tags

  allow :read
end
