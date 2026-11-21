defmodule HologramFeatureTests.Entities.Slip do
  use Hologram.Entity

  alias HologramFeatureTests.Entities.Locker

  attribute :label, :string
  attribute :shared, :boolean, default: false

  relationship :locker, Locker, optional: true

  # Anybody may create a slip, and anybody reads it only once it's shared or while its locker is
  # open, so a browser can create a slip its user may not read.
  allow :create
  allow :read, when: shared == true
  allow :read, when: locker.open == true
end
