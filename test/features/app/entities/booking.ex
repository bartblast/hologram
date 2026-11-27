defmodule HologramFeatureTests.Entities.Booking do
  use Hologram.Entity

  attribute :capacity, :integer
  attribute :check_in, :date
  attribute :check_out, :date
  attribute :confirmed, :boolean, default: false
  attribute :guests, :integer
  attribute :name, :string

  allow :read

  # Only ever asked through can? - confirming is a change to its own field, so the line grants
  # setting that field and nothing else.
  allow :update, as: :confirm, only: [confirmed], when: guests <= capacity
end
