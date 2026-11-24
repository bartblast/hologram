defmodule HologramFeatureTests.Entities.Lid do
  use Hologram.Entity

  # Named only by the implementation of PantryReport for Jar. EntityImpls.Page2 is the one page
  # dispatching that protocol, and it reaches Jar by a relationship name, so Lid syncs only because
  # a row of that type can run the implementation in the browser.
  attribute :sealed, :boolean, default: false

  allow :read
end
