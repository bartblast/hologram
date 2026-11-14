# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Readers.Module13 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyModule1
  alias Hologram.Test.Fixtures.Policy.Readers.Module9

  attribute :open, :boolean, default: false

  relationship :list, Module9, optional: true
  relationship :lists, [Module9]
  relationship :other_list, Module9, optional: true
  relationship :owner, Module14, optional: true
  relationship :parent, PolicyModule1, optional: true

  role :viewer

  allow :read, to: :viewer, when: owner_id == user_id() or open == true
  allow :read, via: {:update, list}
  allow :read, via: parent, when: owner_id == user_id()
  allow :read, to: :viewer, via: {:update, other_list}
  allow :read, when: any(list <- lists, list.open == true and owner_id == user_id())
  allow :read, when: any(list <- lists, list.lead_id == user_id() or list.deputy_id == user_id())
end
