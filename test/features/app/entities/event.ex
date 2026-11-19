defmodule HologramFeatureTests.Entities.Event do
  use Hologram.Entity

  # A day and an instant, both of the kinds the browser has to spell, read and order the way the
  # server does: an instant written in another zone, and a day in a year below 0 or past 9999.
  attribute :held_on, :date, optional: true
  attribute :name, :string
  attribute :starts_at, :datetime, optional: true

  allow :create
  allow :read
end
