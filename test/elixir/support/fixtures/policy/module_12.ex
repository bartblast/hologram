# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module12 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module4
  alias Hologram.Test.Fixtures.Policy.Module5

  relationship :link, Module4, optional: true
  relationship :parent, Module5, optional: true

  allow :publish, via: parent.parent
  allow :update, to: {:viewer, parent.parent}
end
