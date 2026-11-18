# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module37 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module36

  relationship :owner, Module36, optional: true

  allow :update
end
