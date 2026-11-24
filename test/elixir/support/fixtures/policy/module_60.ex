# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module60 do
  use Hologram.Entity

  attribute :blocked, :boolean, default: false

  allow :read
end
