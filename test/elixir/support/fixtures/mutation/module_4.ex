# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Mutation.Module4 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module15

  relationship :secrets, [Module15]

  allow :read
end
