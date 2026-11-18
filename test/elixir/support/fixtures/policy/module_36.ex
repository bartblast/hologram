# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module36 do
  use Hologram.Entity

  attribute :active, :boolean, default: false

  allow :read
end
