# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module13 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module1

  attribute :priority, :integer, optional: true
  attribute :public, :boolean, default: false
  attribute :title, :string

  relationship :parent, Module1, optional: true

  role :editor
  role :owner, extends: :editor, granted_to: :creator

  allow :read, when: public == true
  allow :read, to: [:editor, :owner]
  allow :publish, via: {:read, parent}
  allow :triage, when: priority >= 3
  allow :unlink, when: parent_id == nil
end
