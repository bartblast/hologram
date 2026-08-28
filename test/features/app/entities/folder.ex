defmodule HologramFeatureTests.Entities.Folder do
  use Hologram.Entity

  alias HologramFeatureTests.Policies.PubliclyReadable

  attribute :name, :string
  attribute :public, :boolean, default: false

  policy PubliclyReadable
end
