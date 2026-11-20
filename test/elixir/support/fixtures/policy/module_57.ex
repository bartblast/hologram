# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module57 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module54

  relationship :box, Module54, optional: true

  # Read through its box, so every reader holds the box, but the box is read by the workshop's
  # editors, whom the workshop doesn't admit.
  allow :read, via: box
  allow :update, when: box.workshop.archived == false
end
