# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module45 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module44

  relationship :shelf, Module44, optional: true

  allow :read, when: shelf.vault.owner.active == true
end
