defmodule HologramFeatureTests.Entities.Project do
  use Hologram.Entity

  alias HologramFeatureTests.Entities.Milestone
  alias HologramFeatureTests.Entities.ProjectMember

  attribute :name, :string

  relationship :members, [ProjectMember], inverse: project
  relationship :milestones, [Milestone], inverse: project

  allow :delete, when: none(milestones)
  allow :read, when: any(member <- members, member.user_id == user_id())
end
