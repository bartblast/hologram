# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module28 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module26
  alias Hologram.Test.Fixtures.Entity.Module29

  attribute :body, :string
  attribute :position, :integer

  relationship :channel, Module26, optional: true
  relationship :labels, [Module29]

  allow :read
end
