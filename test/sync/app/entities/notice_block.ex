defmodule HologramSyncTests.Entities.NoticeBlock do
  use Hologram.Entity

  alias HologramSyncTests.Entities.Notice
  alias HologramSyncTests.Entities.User

  relationship :notice, Notice
  relationship :user, User

  allow :read, when: user_id == user_id()
end
