# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module38 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module37

  relationship :vault, Module37, optional: true

  allow :read
end
