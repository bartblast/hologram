# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Mutation.Module8 do
  use Hologram.Entity

  attribute :title, :string, optional: true

  allow :read
  allow :create
  allow :update
end
