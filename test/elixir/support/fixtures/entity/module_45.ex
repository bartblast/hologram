# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module45 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module44

  relationship :folder, Module44, optional: true

  allow :read, when: folder.archived == false
end
