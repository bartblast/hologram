defmodule HologramClusterTests.Entities.Item do
  use Hologram.Entity

  attribute :slug, :string
  attribute :title, :string

  relationship :parent, HologramClusterTests.Entities.Item, optional: true

  # World-readable, so a synced client is sent these rows at all. A registered query over a type
  # with no allow lines does not compile, and what these tests are about is propagation between
  # peers rather than who may see what.
  allow :read
end
