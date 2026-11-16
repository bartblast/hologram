# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Readers.Module17 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Readers.Module16

  attribute :name, :string, optional: true

  relationship :cards, [Module16], inverse: holder

  derived :open_cards, [Module16], fn cards -> filter(cards, done == false) end

  allow :read, when: any(card <- cards, card.author_id == user_id())
  allow :close, when: any(card <- open_cards, card.author_id != user_id())
  allow :lock, when: none(card <- cards, card.done == true or card.author_id == user_id())
  allow :move, when: all(card <- cards, card.author_id == user_id())
end
