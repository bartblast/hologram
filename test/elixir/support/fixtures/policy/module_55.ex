# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module55 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module46

  attribute :visible, :boolean, default: false

  relationship :workshop, Module46, optional: true

  # A reader of the row may not hold the workshop, but the role is looked up by the id the row
  # holds.
  allow :read, when: visible == true
  allow :delete, to: {:owner, workshop}
end
