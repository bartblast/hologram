defmodule HologramFeatureTests.Entities.Workshop do
  use Hologram.Entity

  attribute :archived, :boolean, default: false
  attribute :open, :boolean, default: true

  role :editor
  role :owner

  # Only owners read a workshop, so an editor's browser never holds one.
  allow :read, to: :owner
  allow :update, to: [:editor, :owner]
end
