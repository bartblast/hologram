defmodule HologramFeatureTests.Entities.Label do
  use Hologram.Entity

  alias HologramFeatureTests.Entities.Message

  attribute :name, :string

  relationship :messages, [Message], inverse: labels

  allow :read
end
