defmodule HologramSyncBenchmark.RoleBoardPage do
  use Hologram.Page
  use Hologram.DB

  alias HologramSyncBenchmark.Entities.RoleCard

  route "/role_board"

  layout HologramSyncBenchmark.Components.DefaultLayout

  # The role board case's clients greet with this page. Every card, so the window the compiler
  # derives is the whole table.
  derived :cards, [RoleCard], fn -> sort(RoleCard, position) end

  def template do
    ~HOLO"""
    <p>{length(@cards)} cards</p>
    """
  end
end
