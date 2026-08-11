defmodule HologramFeatureTests.Entities.Document do
  use Hologram.Entity
  use HologramFeatureTests.Policies.PubliclyReadable

  attribute :public, :boolean, default: false
  attribute :title, :string

  role :editor
  role :owner, extends: :editor, creator: true

  allow :read, to: [:editor, :owner]
  allow :manage_roles, to: :owner
end
