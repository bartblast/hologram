# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module20 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module17
  alias Hologram.Test.Fixtures.Policy.Module21
  alias Hologram.Test.Fixtures.Policy.Module24

  attribute :subject, :string, optional: true

  relationship :project, Module17, optional: true
  relationship :shelf, Module24, optional: true
  relationship :tags, [Module21]

  allow :archive, when: none(card <- shelf.cards, card.flagged == true)
  allow :read
  allow :update, when: none(label <- project.labels, label.name == "locked")
end
