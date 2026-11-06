# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module17 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module18
  alias Hologram.Test.Fixtures.Policy.Module19
  alias Hologram.Test.Fixtures.Policy.Module20
  alias Hologram.Test.Fixtures.Policy.Module25

  attribute :name, :string, optional: true
  attribute :public, :boolean, default: false

  relationship :labels, [Module19]
  relationship :members, [Module18], inverse: project
  relationship :profile, Module25, inverse: project
  relationship :tasks, [Module20], inverse: project

  allow :archive, when: none(label <- labels, label.name == "locked")
  allow :close, when: any(tag <- tasks.tags, tag.name == "done")
  allow :feature, when: none(badge <- profile.badges, badge.name == "banned")
  allow :publish, when: none(card <- tasks.shelf.cards, card.flagged == true)
  allow :read, when: public == true or any(member <- members, member.user_id == user_id())
  allow :update, when: any(member <- members, member.seat == "full")
end
