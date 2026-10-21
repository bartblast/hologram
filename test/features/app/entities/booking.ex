defmodule HologramFeatureTests.Entities.Booking do
  use Hologram.Entity

  attribute :capacity, :integer
  attribute :check_in, :date
  attribute :check_out, :date
  attribute :guests, :integer
  attribute :name, :string

  allow :confirm, when: guests <= capacity
  allow :read
end
