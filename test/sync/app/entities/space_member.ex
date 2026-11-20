defmodule HologramSyncTests.Entities.SpaceMember do
  use Hologram.Entity

  alias HologramSyncTests.Entities.Space
  alias HologramSyncTests.Entities.User

  relationship :space, Space
  relationship :user, User

  allow :read, when: user_id == user_id()
end
