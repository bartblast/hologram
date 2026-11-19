defmodule HologramFeatureTests.Entities.Bulletin do
  use Hologram.Entity

  attribute :title, :string
  attribute :topic, :string

  role :member
  role :owner, extends: :member

  # Each update line covers one field, so a write is judged by what it changes: a member may set
  # the topic, and only an owner may rename the bulletin.
  allow :read, to: :member
  allow :update, as: :set_topic, only: [:topic], to: :member
  allow :update, as: :rename, only: [:title], to: :owner
end
