# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module30 do
  use Hologram.Entity

  attribute :body, :string

  relationship :follows, [__MODULE__]
  relationship :followers, [__MODULE__], inverse: follows
  relationship :parent, __MODULE__, optional: true
  relationship :replies, [__MODULE__], inverse: parent, sort: body

  allow :read
end
