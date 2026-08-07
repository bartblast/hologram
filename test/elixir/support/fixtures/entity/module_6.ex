# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module6 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module3

  relationship :a, [Module3]
end
