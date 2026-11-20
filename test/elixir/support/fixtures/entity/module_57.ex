# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module57 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module56

  attribute :position, :integer

  relationship :owner, Module56, optional: true

  derived :later_count, :integer, fn owner, position ->
    owner.items
    |> filter(position > ^position)
    |> count()
  end

  allow :read
end
