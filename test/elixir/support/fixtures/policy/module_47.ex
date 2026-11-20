# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module47 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module46

  relationship :workshop, Module46, optional: true

  allow :read, to: {:owner, workshop}
end
