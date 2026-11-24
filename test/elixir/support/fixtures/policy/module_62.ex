# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module62 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module63

  relationship :members, [Module63]
end
