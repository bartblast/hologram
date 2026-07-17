# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module3 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module2

  relationship :c, Module1
  relationship :a, [Module2]
  relationship :b, Module2, optional: true
end
