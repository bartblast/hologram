# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module28 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module26

  attribute :subject, :string, optional: true

  relationship :space, Module26, optional: true

  allow :close, when: any(comment <- space.comments, comment.flagged == true)
  allow :update, when: none(comment <- space.comments, comment.flagged == true)
end
