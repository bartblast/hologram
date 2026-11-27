# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module38 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module15
  alias Hologram.Test.Fixtures.Policy.Module36

  attribute :archived, :boolean, default: false
  attribute :name, :string, optional: true
  attribute :sent_count, :integer, default: 0
  attribute :topic, :string, optional: true

  relationship :owner, Module14, optional: true
  relationship :parent, Module36, optional: true
  relationship :tags, [Module15]

  allow :read
  allow :update, as: :set_topic, only: [topic, tags], when: archived == false
  allow :update, as: :rename, only: [name, parent], when: owner_id == user_id()
  allow :update, except: [archived, owner], when: name == "open"
  allow :update, when: owner_id == user_id() and archived == true
end
