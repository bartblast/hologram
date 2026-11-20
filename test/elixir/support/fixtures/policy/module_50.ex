# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module50 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module46

  relationship :workshop, Module46, optional: true

  # Read through its workshop, so every reader of a crate holds the workshop, and every session
  # reads every site.
  allow :read, via: workshop
  allow :update, via: workshop
  allow :delete, when: workshop.archived == false and workshop.site.closed == false
end
