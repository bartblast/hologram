# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module22 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module23

  relationship :cards, [Module23], inverse: board

  derived :top_cards, [Module23], fn cards ->
    cards
    |> sort(rank: :desc)
    |> take(2)
  end

  allow :read, when: any(card <- top_cards, card.flagged == true)
end
