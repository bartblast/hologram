# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module38 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module37

  attribute :pinned, :boolean

  relationship :author, Module1, optional: true
  relationship :channel, Module37

  derived :sibling_count, :integer, fn channel -> count(channel.messages) end

  allow :read
  allow :update, when: channel.name == "general"
end
