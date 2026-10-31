# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module26 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module27
  alias Hologram.Test.Fixtures.Entity.Module28

  attribute :name, :string

  relationship :messages, [Module28], inverse: channel, sort: position
  relationship :topic, Module27, inverse: channel

  allow :read
end
