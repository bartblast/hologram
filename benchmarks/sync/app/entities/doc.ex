defmodule HologramSyncBenchmark.Entities.Doc do
  use Hologram.Entity

  alias HologramSyncBenchmark.Entities.Project

  attribute :position, :integer
  attribute :title, :string

  relationship :project, Project

  # A project's members read its docs while it isn't archived, so archiving it is one write that
  # hides every doc from every member, and unarchiving it shows them all again.
  allow :read,
    when:
      project.archived == false and any(member <- project.members, member.user_id == user_id())
end
