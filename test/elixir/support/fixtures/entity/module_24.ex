# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module24 do
  use Hologram.Entity

  attribute :ends_on, :date, optional: true
  attribute :level, :enum, values: [:low, :medium, :high], optional: true
  attribute :priority, :enum, values: [:low, :medium, :high], optional: true
  attribute :starts_on, :date, optional: true
  attribute :tier, :enum, values: [:low, :high], optional: true

  allow :read
end
