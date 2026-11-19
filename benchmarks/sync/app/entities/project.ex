defmodule HologramSyncBenchmark.Entities.Project do
  use Hologram.Entity

  alias HologramSyncBenchmark.Entities.Doc
  alias HologramSyncBenchmark.Entities.ProjectMember

  attribute :archived, :boolean, default: false
  attribute :name, :string

  relationship :docs, [Doc], inverse: project
  relationship :members, [ProjectMember], inverse: project

  allow :read, when: any(member <- members, member.user_id == user_id())
end
