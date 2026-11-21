# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module56 do
  use Hologram.Entity

  attribute :closed, :boolean, default: false

  allow :read
end
