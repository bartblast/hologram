# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Readers.Module11 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Readers.Module5

  relationship :owned, Module5, optional: true

  allow :read, via: owned
end
