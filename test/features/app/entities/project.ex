defmodule HologramFeatureTests.Entities.Project do
  use Hologram.Entity

  alias HologramFeatureTests.Entities.ProjectMember

  attribute :name, :string

  relationship :members, [ProjectMember], inverse: project
end
