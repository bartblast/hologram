defmodule HologramSyncBenchmark.BoardPage do
  use Hologram.Page
  use Hologram.DB

  alias HologramSyncBenchmark.Entities.Card

  route "/board"

  layout HologramSyncBenchmark.Components.DefaultLayout

  # The board case's clients greet with this page. Every card, so the window the compiler derives
  # is the whole table.
  derived :cards, [Card], fn -> sort(Card, position) end

  def template do
    ~HOLO"""
    <p>{length(@cards)} cards</p>
    """
  end
end
