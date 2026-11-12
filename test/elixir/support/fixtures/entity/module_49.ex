# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module49 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module48

  relationship :items, [Module48], inverse: owner

  allow :read
end
