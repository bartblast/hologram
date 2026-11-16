defmodule HologramFeatureTests.Entities.Report do
  use Hologram.Entity

  attribute :reviewed, :boolean, default: false, server_only: true
  attribute :title, :string

  allow :read, when: reviewed == true
end
