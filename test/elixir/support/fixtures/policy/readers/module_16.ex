# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Readers.Module16 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Policy.Readers.Module15
  alias Hologram.Test.Fixtures.Policy.Readers.Module17

  attribute :done, :boolean, default: false

  relationship :author, Module14, optional: true
  relationship :board, Module15, optional: true
  relationship :holder, Module17, optional: true
  relationship :reviewer, Module14, optional: true

  allow :read
end
