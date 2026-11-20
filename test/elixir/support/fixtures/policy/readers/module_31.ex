# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Readers.Module31 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Readers.Module30

  relationship :workshop, Module30, optional: true

  allow :read, to: {:owner, workshop}
end
