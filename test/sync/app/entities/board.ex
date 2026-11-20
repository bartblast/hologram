defmodule HologramSyncTests.Entities.Board do
  use Hologram.Entity

  alias HologramSyncTests.Entities.Card
  alias HologramSyncTests.Entities.Space

  attribute :archived, :boolean, default: false
  attribute :name, :string

  relationship :cards, [Card], inverse: board
  relationship :space, Space

  role :viewer

  allow :read, to: :viewer

  allow :read,
    when: archived == false and any(member <- space.members, member.user_id == user_id())
end
