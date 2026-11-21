defmodule HologramSyncTests.Entities.Space do
  use Hologram.Entity

  alias HologramSyncTests.Entities.Board
  alias HologramSyncTests.Entities.SpaceMember

  attribute :name, :string

  relationship :boards, [Board], inverse: space
  relationship :members, [SpaceMember], inverse: space

  allow :read, when: any(member <- members, member.user_id == user_id())
end
