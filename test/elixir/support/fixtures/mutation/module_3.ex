# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Mutation.Module3 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Mutation.Module2

  relationship :b, Module2, optional: true

  allow :read
end
