# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module17 do
  use Hologram.Entity

  attribute :priority, :enum, values: [:low, :medium, :high], optional: true
  attribute :label, :string
end
