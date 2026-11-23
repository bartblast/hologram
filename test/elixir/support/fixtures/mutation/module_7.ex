# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Mutation.Module7 do
  use Hologram.Entity

  attribute :held_on, :date, optional: true
  attribute :starts_at, :datetime, optional: true
  attribute :title, :string, optional: true

  allow :read
  allow :create
  allow :update
end
