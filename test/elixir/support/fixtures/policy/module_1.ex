# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module1 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Policy.Module2

  attribute :priority, :integer, optional: true
  attribute :public, :boolean, default: false

  relationship :author, Module14, optional: true
  relationship :parent, Module2, optional: true

  role :editor
  role :maintainer, granted_to: :creator
  role :owner, extends: :editor, granted_to: :creator
  role :viewer

  allow :read, when: public == true
  allow :read, to: [:viewer, {:admin, Module2}]
  allow :update, to: :editor, when: priority >= 3
  allow :delete, to: {:admin, parent}
  allow :publish, via: parent
  allow :grant_role, to: :owner
  allow :revoke_role, to: :owner
  allow :archive, when: author_id == user_id()
end
