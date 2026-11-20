defmodule HologramFeatureTests.Entities.Sticker do
  use Hologram.Entity

  # A docket's to-many target of its own, so the docket's join table holds a foreign key to no
  # table another test truncates alone.
  attribute :name, :string

  allow :read
end
