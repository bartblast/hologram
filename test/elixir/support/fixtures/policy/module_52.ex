# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module52 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module46

  relationship :workshop, Module46, optional: true

  # No read line, so no client is sent a bin.
  allow :update, when: workshop.archived == false
end
