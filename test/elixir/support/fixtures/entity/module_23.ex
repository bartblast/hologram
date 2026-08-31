# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module23 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module22

  relationship :a, Module22, optional: true

  allow :read
end
