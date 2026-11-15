# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Readers.Module6 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Readers.Module7

  relationship :blocks, [Module7], inverse: subject

  allow :read, when: none(block <- blocks, block.user_id == user_id())
end
