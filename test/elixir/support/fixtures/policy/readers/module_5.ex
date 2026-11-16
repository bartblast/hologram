# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Readers.Module5 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module14

  relationship :owner, Module14, optional: true

  allow :read, when: owner_id != user_id()
end
