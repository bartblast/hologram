# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module22 do
  use Hologram.Entity

  attribute :opens_at, :time, optional: true

  allow :read
end
