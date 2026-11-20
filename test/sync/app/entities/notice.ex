defmodule HologramSyncTests.Entities.Notice do
  use Hologram.Entity

  alias HologramSyncTests.Entities.NoticeBlock

  attribute :title, :string

  relationship :blocks, [NoticeBlock], inverse: notice

  # Readable by every signed-in user its blocks don't name - a rule nothing bounds, which sync
  # answers apart from the rules that list their readers. An anonymous session reads none, since a
  # `none` naming the acting user is false without one.
  allow :read, when: none(block <- blocks, block.user_id == user_id())
end
