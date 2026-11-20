# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module51 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module46

  relationship :workshop, Module46, optional: true

  # Read by the workshop's members, who may read the workshop, so every reader of a box holds it.
  allow :read, to: {:member, workshop}
  allow :update, when: workshop.archived == false
  allow :delete, to: {:owner, workshop}
end
