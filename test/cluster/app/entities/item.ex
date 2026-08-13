defmodule HologramClusterTests.Entities.Item do
  use Hologram.Entity

  attribute :slug, :string
  attribute :title, :string

  relationship :parent, HologramClusterTests.Entities.Item, optional: true
end
