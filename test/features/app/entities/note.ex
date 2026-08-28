defmodule HologramFeatureTests.Entities.Note do
  use Hologram.Entity

  alias HologramFeatureTests.Entities.User

  attribute :body, :string
  attribute :pinned, :boolean, default: false

  relationship :author, User

  role :editor
  role :owner, extends: :editor, granted_to: :creator

  allow :read, to: :editor
  allow :create, author_id: user_id()
  allow :delete, to: :owner
  allow :manage_roles, to: :owner
  allow :pin, to: :editor, pinned: false
end
