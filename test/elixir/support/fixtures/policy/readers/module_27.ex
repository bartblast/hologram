# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Readers.Module27 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Readers.Module26

  relationship :crate, Module26, optional: true

  allow :update
end
