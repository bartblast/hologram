defmodule HologramFeatureTests.Entities.Decal do
  use Hologram.Entity

  attribute :name, :string
  attribute :shown, :boolean, default: true

  # Hiding a decal on the server takes it out of the browser, whatever pairs name it.
  allow :read, when: shown == true
end
