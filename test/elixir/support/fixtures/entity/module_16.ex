# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module16 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module15

  attribute :name, :string, optional: true

  relationship :secrets, [Module15]

  allow :read
end
