# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Readers.Module4 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Readers.Module1

  relationship :project, Module1, optional: true

  allow :read, via: project
end
