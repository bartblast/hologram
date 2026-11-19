defmodule HologramFeatureTests.Entities.Vault do
  use Hologram.Entity

  attribute :open, :boolean, default: false

  role :keeper

  # No read line, so no browser ever holds a vault.
  allow :update, to: :keeper
end
