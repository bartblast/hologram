# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module25 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module13
  alias Hologram.Test.Fixtures.Entity.Module15
  alias Hologram.Test.Fixtures.Entity.Module24
  alias Hologram.Test.Fixtures.Entity.Module4

  relationship :e, Module24, optional: true
  relationship :f, Module4
  relationship :g, Module15, optional: true
  relationship :h, Module13, optional: true

  allow :read
end
