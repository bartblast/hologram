# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module36 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module14

  attribute :archived, :boolean, default: false
  attribute :name, :string, optional: true

  relationship :owner, Module14, optional: true

  allow :read
  allow :update, as: :archive, when: owner_id == user_id()
  allow :update, when: name == "open"
end
