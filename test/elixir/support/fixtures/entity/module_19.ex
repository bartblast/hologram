# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module19 do
  use Hologram.Entity

  attribute :code, :string, optional: true, unique: true
  attribute :slug, :string, unique: true

  allow :read
end
