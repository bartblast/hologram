defmodule HologramFeatureTests.Entities.Ticket do
  use Hologram.Entity

  attribute :priority, :enum, values: [:low, :medium, :high]
  attribute :title, :string

  allow :read
end
