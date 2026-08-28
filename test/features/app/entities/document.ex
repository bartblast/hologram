defmodule HologramFeatureTests.Entities.Document do
  use Hologram.Entity

  policy HologramFeatureTests.Policies.PubliclyReadable

  alias HologramFeatureTests.Entities.Folder

  attribute :api_token, :string, optional: true, server_only: true
  attribute :public, :boolean, default: false
  attribute :title, :string

  relationship :folder, Folder, optional: true

  role :editor
  role :owner, extends: :editor, granted_to: :creator

  allow :read, to: [:editor, :owner]
  allow :manage_roles, to: :owner
end
