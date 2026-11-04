# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module41 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module40

  attribute :public, :boolean

  relationship :tags, [Module2]
  relationship :team, Module40, optional: true

  allow :read, when: public == true
end
