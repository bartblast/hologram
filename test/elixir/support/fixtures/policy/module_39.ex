# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module39 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module38

  relationship :shelf, Module38, optional: true

  allow :read, when: shelf.vault.owner.active == true
end
