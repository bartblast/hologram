# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module58 do
  use Hologram.Entity

  attribute :a, :id
  attribute :b, :uuid, optional: true

  derived :a_copy, :id, fn a -> a end

  allow :read
end
