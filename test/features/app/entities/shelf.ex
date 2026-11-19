defmodule HologramFeatureTests.Entities.Shelf do
  use Hologram.Entity

  alias HologramFeatureTests.Entities.Vault

  relationship :vault, Vault, optional: true

  # No read line, so no browser ever holds a shelf. The create line reads nothing through the
  # vault: a rule for any other operation reading a type nobody may read fails the build.
  allow :create
end
