# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module2 do
  use Hologram.Entity

  attribute :c, :string
  attribute :a, :boolean, default: false
  attribute :b, :integer, optional: true
end
