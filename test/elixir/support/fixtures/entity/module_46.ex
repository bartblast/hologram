# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module46 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module44

  relationship :held, [Module44], inverse: holder

  allow :read
end
