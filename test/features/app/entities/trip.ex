defmodule HologramFeatureTests.Entities.Trip do
  use Hologram.Entity

  attribute :archived, :boolean, default: false
  attribute :name, :string

  role :editor

  # Open, the way a root type's create rule usually is - nobody holds a role on a row before it
  # exists. A stop names the trip's update rule rather than asking this one.
  allow :create
  allow :read
  allow :update, to: :editor, when: archived == false
end
