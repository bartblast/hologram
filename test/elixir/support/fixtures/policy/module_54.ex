# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module54 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module46

  relationship :workshop, Module46, optional: true

  # An editor of the workshop may not read it.
  allow :read, to: {:editor, workshop}
  allow :update, when: workshop.archived == false
end
