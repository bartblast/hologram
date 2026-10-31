# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module27 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module26

  attribute :code, :string, optional: true, unique: true
  attribute :summary, :string

  relationship :channel, Module26, optional: true, unique: true

  allow :read
end
