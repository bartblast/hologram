# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module43 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module42

  relationship :owner, Module42, optional: true

  allow :update
end
