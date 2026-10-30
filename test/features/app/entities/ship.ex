defmodule HologramFeatureTests.Entities.Ship do
  use Hologram.Entity

  attribute :archived, :boolean, default: false
  attribute :name, :string

  role :captain

  # No page queries ships: a cabin's rename rule reads its ship, so a client checking it holds the
  # ships only because the rule reads them.
  allow :create
  allow :read
  allow :update, to: :captain, when: archived == false
end
