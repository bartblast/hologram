# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module18 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Policy.Module17

  attribute :seat, :string, optional: true

  relationship :project, Module17, optional: true
  relationship :user, Module14, optional: true

  allow :read, when: seat == "full"
end
