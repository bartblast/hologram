defmodule HologramFeatureTests.Entities.Folder do
  use Hologram.Entity
  use HologramFeatureTests.Policies.PubliclyReadable

  attribute :name, :string
  attribute :public, :boolean, default: false
end
