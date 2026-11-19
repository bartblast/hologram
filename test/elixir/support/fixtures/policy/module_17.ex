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

  allow :update, as: :archive, only: [:name], when: none(label <- labels, label.name == "locked")
  allow :update, as: :close, only: [:name], when: any(tag <- tasks.tags, tag.name == "done")

  allow :update,
    as: :feature,
    only: [:name],
    when: none(badge <- profile.badges, badge.name == "banned")

  allow :update,
    as: :publish,
    only: [:name],
    when: none(card <- tasks.shelf.cards, card.flagged == true)

  allow :read, when: public == true or any(member <- members, member.user_id == user_id())
  allow :update, when: any(member <- members, member.seat == "full")
end
