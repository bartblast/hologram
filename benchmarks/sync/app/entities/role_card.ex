defmodule HologramSyncBenchmark.Entities.RoleCard do
  use Hologram.Entity

  alias HologramSyncBenchmark.Entities.RoleBoard

  attribute :position, :integer
  attribute :title, :string

  relationship :board, RoleBoard

  # Read when the board is: every client's user holds the role on the one board, so every client
  # gets every card, as on the plain board, but answering whether it may read a card means
  # reading the card's board and asking for the user's grants on it.
  allow :read, via: {:read, board}
end
