# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module13 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module2

  relationship :parent, Module2, optional: true

  allow :read, to: {:member, parent}
end
