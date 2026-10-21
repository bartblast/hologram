# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module7 do
  use Hologram.Entity

  attribute :capacity, :integer
  attribute :guests, :integer

  allow :update, when: guests <= capacity
end
