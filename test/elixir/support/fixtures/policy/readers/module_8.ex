# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Readers.Module8 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Policy.Readers.Module9

  attribute :archived, :boolean, default: false
  attribute :open, :boolean, default: false

  relationship :lists, [Module9], inverse: board
  relationship :owner, Module14, optional: true
  relationship :sponsor, Module14, optional: true

  allow :read, when: any(list <- lists, any(card <- list.cards, card.assignee_id == user_id()))
  allow :read, when: any(list <- lists, list.lead_id == user_id() or list.deputy_id == user_id())
  allow :read, when: any(card <- lists.cards, card.reviewer_id == user_id())
  allow :read, when: any(list <- lists, list.open == true and owner_id == user_id())

  allow :read,
    when: (open == true or owner_id == user_id()) and (archived == false or owner_id == user_id())

  allow :read, when: sponsor.id == user_id()

  allow :read,
    when: any(list <- lists, any(card <- list.open_cards, card.watcher_id == user_id()))
end
