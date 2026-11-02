defmodule HologramFeatureTests.Entities.Post do
  use Hologram.Entity

  attribute :body, :string
  attribute :deleted, :boolean, default: false

  relationship :parent, __MODULE__, optional: true
  relationship :replies, [__MODULE__], inverse: parent

  allow :read
end
