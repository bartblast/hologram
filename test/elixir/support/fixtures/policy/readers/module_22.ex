# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Readers.Module22 do
  use Hologram.Entity

  attribute :name, :string, optional: true

  role :member

  allow :read
end
