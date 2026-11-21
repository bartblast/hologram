defmodule HologramFeatureTests.Entities.Permit do
  use Hologram.Entity

  alias HologramFeatureTests.Entities.Tool

  attribute :approved, :boolean, default: false

  relationship :tool, Tool

  allow :read, to: {:owner, tool.workshop}
end
