# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module20 do
  use Hologram.Entity

  attribute :count, :integer, default: 0
  attribute :label, :string, optional: true

  allow :read
  allow :update
end
