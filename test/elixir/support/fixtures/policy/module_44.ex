# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module44 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module43

  relationship :vault, Module43, optional: true

  allow :read
end
