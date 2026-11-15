# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Readers.Module2 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Policy.Readers.Module1

  relationship :project, Module1, optional: true
  relationship :user, Module14, optional: true

  allow :read, when: user_id == user_id()
end
