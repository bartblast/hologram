defmodule HologramFeatureTests.Entities.ProjectMember do
  use Hologram.Entity

  alias HologramFeatureTests.Entities.Project
  alias HologramFeatureTests.Entities.User

  attribute :seat, :enum, values: [:viewer, :full]

  relationship :project, Project
  relationship :user, User

  allow :read, when: user_id == user_id()
end
