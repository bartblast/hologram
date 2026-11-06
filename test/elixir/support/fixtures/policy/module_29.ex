# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module29 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module27

  attribute :name, :string, optional: true

  relationship :comments, [Module27], inverse: marks

  allow :update, when: none(comment <- comments, comment.flagged == true)
end
