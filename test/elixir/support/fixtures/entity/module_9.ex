# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module9 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module8

  relationship :a, [Module8]
end
