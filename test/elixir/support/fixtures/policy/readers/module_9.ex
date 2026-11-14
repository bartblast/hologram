# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Readers.Module9 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Policy.Readers.Module10
  alias Hologram.Test.Fixtures.Policy.Readers.Module8

  attribute :open, :boolean, default: false

  relationship :board, Module8, optional: true
  relationship :cards, [Module10], inverse: list
  relationship :deputy, Module14, optional: true
  relationship :lead, Module14, optional: true

  allow :read
  allow :update, when: lead_id == user_id()
end
