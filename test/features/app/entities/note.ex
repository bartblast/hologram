defmodule HologramFeatureTests.Entities.Note do
  use Hologram.Entity

  alias HologramFeatureTests.Entities.User

  attribute :body, :string
  attribute :pinned, :boolean, default: false

  relationship :author, User

  role :editor
  role :owner, extends: :editor, granted_to: :creator

  allow :read, to: :editor
  allow :create, when: author_id == user_id()
  allow :delete, to: :owner
  allow :grant_role, to: :owner
  allow :revoke_role, to: :owner
  allow :pin, to: :editor, when: pinned == false
end
