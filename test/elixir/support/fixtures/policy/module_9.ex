# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module9 do
  use Hologram.Entity

  attribute :archived, :boolean, default: false

  relationship :parent, Hologram.Test.Fixtures.Policy.Module9, optional: true

  allow :create
  allow :read, via: {:update, parent}
  allow :update, when: archived == false
end
