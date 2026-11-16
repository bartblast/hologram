defmodule HologramFeatureTests.Entities.Inspection do
  use Hologram.Entity

  attribute :passed_on, :date, optional: true, server_only: true
  attribute :title, :string

  allow :read, when: passed_on != nil
end
