defmodule HologramFeatureTests.Entities.Milestone do
  use Hologram.Entity

  alias HologramFeatureTests.Entities.Project

  attribute :title, :string

  relationship :project, Project

  allow :create, when: any(member <- project.members, member.user_id == user_id())
  allow :read, when: any(member <- project.members, member.user_id == user_id())

  allow :update,
    when: any(member <- project.members, member.user_id == user_id() and member.seat == :full)
end
