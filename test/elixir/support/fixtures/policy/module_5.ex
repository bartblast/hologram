# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module5 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module1

  relationship :parent, Module1, optional: true

  allow :read, via: :parent
end
