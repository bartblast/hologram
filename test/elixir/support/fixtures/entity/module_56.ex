# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module56 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module57

  relationship :items, [Module57], inverse: owner

  derived :rest, [Module57], fn items ->
    items
    |> sort(later_count)
    |> skip(1)
  end

  allow :read
end
