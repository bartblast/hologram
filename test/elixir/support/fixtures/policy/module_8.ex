# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module8 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module5

  relationship :parent, Module5, optional: true

  allow :read, via: parent
end
