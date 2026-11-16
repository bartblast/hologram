# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Readers.Module15 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Readers.Module16

  attribute :name, :string, optional: true

  relationship :cards, [Module16], inverse: board

  derived :open_cards, [Module16], fn cards -> filter(cards, done == false) end

  allow :read
  allow :archive, when: none(card <- cards, card.author_id == user_id())
  allow :close, when: any(card <- open_cards, card.author_id == user_id())
  allow :delete, when: none(cards)
  allow :hide, when: all(card <- cards, card.author_id != user_id())

  allow :pin,
    when: none(card <- cards, card.author_id == user_id() or card.reviewer_id == user_id())

  allow :review, when: any(card <- open_cards, card.done == false)
  allow :update, when: none(card <- cards, card.author_id == user_id())
end
