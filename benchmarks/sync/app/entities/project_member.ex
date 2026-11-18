defmodule HologramSyncBenchmark.Entities.ProjectMember do
  use Hologram.Entity

  alias HologramSyncBenchmark.Entities.Project
  alias HologramSyncBenchmark.Entities.User

  relationship :project, Project
  relationship :user, User

  allow :read, when: user_id == user_id()
end
