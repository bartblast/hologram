# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module3 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module1

  relationship :children, [Module1]

  allow :read
end
