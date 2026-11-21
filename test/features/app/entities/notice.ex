defmodule HologramFeatureTests.Entities.Notice do
  use Hologram.Entity

  attribute :title, :string

  allow :create
  allow :read
end
