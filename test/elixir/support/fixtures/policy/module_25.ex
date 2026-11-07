# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module25 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module17
  alias Hologram.Test.Fixtures.Policy.Module19

  relationship :badges, [Module19]
  relationship :project, Module17, optional: true, unique: true

  allow :read
end
