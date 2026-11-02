# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module31 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module17

  attribute :floor, :enum, values: [:low, :medium, :high], optional: true
  attribute :tier, :enum, values: [:low, :high], optional: true

  relationship :items, [Module17]

  allow :read
end
