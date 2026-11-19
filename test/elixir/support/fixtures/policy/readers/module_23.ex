# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Readers.Module23 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Readers.Module22

  relationship :team, Module22, optional: true

  allow :update
end
