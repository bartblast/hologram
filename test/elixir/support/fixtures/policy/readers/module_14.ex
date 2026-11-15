# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Readers.Module14 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Readers.Module12

  relationship :board, Module12, optional: true

  allow :read, via: board
end
