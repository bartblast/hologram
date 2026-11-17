defmodule HologramSyncBenchmark.Entities.RoleBoard do
  use Hologram.Entity

  alias HologramSyncBenchmark.Entities.RoleCard

  attribute :name, :string

  relationship :cards, [RoleCard], inverse: board

  role :viewer

  # A board its members may read, each holding the role on it - how an app shares a board with
  # the people on it.
  allow :read, to: :viewer
end
