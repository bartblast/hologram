# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module47 do
  use Hologram.Entity

  attribute :count, :integer, min: 1
  attribute :email, :string, format: ~r/@/s, optional: true

  allow :read
end
