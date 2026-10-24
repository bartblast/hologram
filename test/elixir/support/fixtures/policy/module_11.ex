# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module11 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module10

  relationship :parent, Module10, optional: true

  allow :create, via: {:update, parent}
end
