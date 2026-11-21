defmodule HologramFeatureTests.Entities.Bench do
  use Hologram.Entity

  alias HologramFeatureTests.Entities.Workshop

  relationship :workshop, Workshop, optional: true

  allow :read, to: {:owner, workshop}
end
