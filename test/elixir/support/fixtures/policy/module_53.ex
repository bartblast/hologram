# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module53 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module46

  attribute :visible, :boolean, default: false

  relationship :workshop, Module46, optional: true

  # One read rule reads through the workshop and the other doesn't, so a reader of the row may not
  # hold the workshop.
  allow :read, via: workshop
  allow :read, when: visible == true
  allow :update, when: workshop.archived == false
end
