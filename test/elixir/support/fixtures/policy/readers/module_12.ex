# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Readers.Module12 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyModule1
  alias Hologram.Test.Fixtures.Policy.Module19
  alias Hologram.Test.Fixtures.Policy.Readers.Module9

  attribute :archived, :boolean, default: false
  attribute :open, :boolean, default: false

  relationship :label, Module19, optional: true
  relationship :list, Module9, optional: true
  relationship :lists, [Module9]
  relationship :owner, Module14, optional: true
  relationship :parent, PolicyModule1, optional: true

  role :viewer

  allow :read, when: any(list <- lists, list.lead_id == user_id() or list.open == true)
  allow :read, when: any(list <- lists, list.lead_id != user_id())
  allow :read, when: all(list <- lists, list.lead_id == user_id())

  allow :read,
    when: open == true or (archived == false and (owner_id == user_id() or open == false))

  allow :read, to: :viewer, when: owner_id == user_id() or open == true
  allow :read, via: label
  allow :read, via: {:update, list}
  allow :read, via: parent, when: owner_id == user_id()
  allow :read, to: :viewer, via: {:update, list}
end
