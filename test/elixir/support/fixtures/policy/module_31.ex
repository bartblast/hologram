# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module31 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module30
  alias Hologram.Test.Fixtures.Policy.Module32

  attribute :flagged, :boolean, default: false
  attribute :note, :string, optional: true
  attribute :open, :boolean, default: false
  attribute :rank, :integer, optional: true

  relationship :deck, Module30, optional: true
  relationship :tags, [Module32]

  derived :tag_count, :integer, fn tags -> count(tags) end

  allow :read
  allow :update, when: any(card <- deck.hot_cards, card.flagged == true)
end
