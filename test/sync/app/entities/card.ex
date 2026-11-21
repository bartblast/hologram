defmodule HologramSyncTests.Entities.Card do
  use Hologram.Entity

  alias HologramSyncTests.Entities.Board
  alias HologramSyncTests.Entities.Tag

  attribute :title, :string

  relationship :board, Board
  relationship :tags, [Tag]

  allow :read, via: {:read, board}
end
