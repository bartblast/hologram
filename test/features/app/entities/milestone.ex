defmodule HologramFeatureTests.Entities.Milestone do
  use Hologram.Entity

  alias HologramFeatureTests.Entities.Project

  attribute :title, :string

  relationship :project, Project

  allow :read, when: any(member <- project.members, member.user_id == user_id())
end
