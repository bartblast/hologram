# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module24 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module23

  relationship :cards, [Module23], inverse: shelf
end
