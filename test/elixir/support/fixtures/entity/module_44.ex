# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module44 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module46

  attribute :archived, :boolean

  relationship :holder, Module46, optional: true
end
