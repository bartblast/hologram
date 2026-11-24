defmodule HologramSyncBenchmark.ProbePage do
  use Hologram.Page
  use Hologram.DB

  alias HologramSyncBenchmark.Entities.Card

  route "/probe"

  layout HologramSyncBenchmark.Components.DefaultLayout

  # What the probe asks for while a case runs: an ordinary page render with one primary key lookup
  # through the app's own database pool, to show whether sync's work slows the app's requests. An
  # id no row has, so it costs the same whichever case seeded what, and scans nothing.
  derived :cards, [Card], fn -> filter(Card, id == "00000000-0000-0000-0000-000000000000") end

  def template do
    ~HOLO"""
    <p>{length(@cards)} cards</p>
    """
  end
end
