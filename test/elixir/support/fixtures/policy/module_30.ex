# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module30 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module31

  attribute :name, :string, optional: true

  relationship :cards, [Module31], inverse: deck

  derived :hot_cards, [Module31], fn cards ->
    cards
    |> filter(open == true and tag_count > 0)
    |> sort(rank: :desc)
    |> take(2)
  end
end
