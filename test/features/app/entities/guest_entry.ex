defmodule HologramFeatureTests.Entities.GuestEntry do
  use Hologram.Entity

  # A visitor may create one, and its creator takes a role on it - so a session the data layer reads
  # as a visitor, like one signed in with an app's own user id, writes it and takes no role.
  attribute :text, :string

  role :owner, granted_to: :creator

  allow :create
  allow :read
end
