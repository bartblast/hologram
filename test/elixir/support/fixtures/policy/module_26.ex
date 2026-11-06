# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module26 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module27
  alias Hologram.Test.Fixtures.Policy.Module28

  attribute :name, :string, optional: true

  relationship :comments, [Module27], inverse: space
  relationship :tickets, [Module28], inverse: space

  allow :delete, when: none(comment <- comments, comment.flagged == true)
  # Module28's :close reads it through an any, which a browser answers from rows it holds.
  allow :read
end
