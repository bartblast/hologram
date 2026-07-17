# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module2 do
  use Hologram.Entity

  attr :c, :string
  attr :a, :boolean, default: false
  attr :b, :integer, optional: true
end
