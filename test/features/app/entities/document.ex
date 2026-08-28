defmodule HologramFeatureTests.Entities.Document do
  use Hologram.Entity

  alias HologramFeatureTests.Entities.Folder
  alias HologramFeatureTests.Policies.Editable
  alias HologramFeatureTests.Policies.PubliclyReadable

  attribute :api_token, :string, optional: true, server_only: true
  attribute :public, :boolean, default: false
  attribute :title, :string

  relationship :folder, Folder, optional: true

  policy Editable
  policy PubliclyReadable

  role :owner, granted_to: :creator
end
