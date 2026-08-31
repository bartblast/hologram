defmodule HologramFeatureTests.Policies.ReadableThroughFolder do
  use Hologram.Policy

  allow :read, via: :folder
end
