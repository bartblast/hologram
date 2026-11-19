defmodule HologramFeatureTests.Entities.Parcel do
  use Hologram.Entity

  alias HologramFeatureTests.Entities.Shelf
  alias HologramFeatureTests.Entities.Vault

  attribute :label, :string

  relationship :shelf, Shelf, optional: true
  relationship :vault, Vault, optional: true

  # Each line reads a row of a type no browser holds: a condition on the vault, a role held on the
  # vault the shelf names, and the vault's own update rule.
  allow :read, when: vault.open == true
  allow :read, to: {:keeper, shelf.vault}
  allow :read, via: {:update, vault}
end
