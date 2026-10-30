# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module15 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module12

  relationship :origin, Module12, optional: true

  allow :read
end
