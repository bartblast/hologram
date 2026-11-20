# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Mutation.Module6 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module15

  attribute :status, :string, optional: true

  relationship :tags, [Module15]

  allow :read
  allow :update, when: status == "open" and none(tag <- tags, tag.label == "locked")
end
