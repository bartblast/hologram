# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Mutation.Module5 do
  use Hologram.Entity

  attribute :title, :string, optional: true

  role :maintainer, granted_to: :creator

  allow :read
  allow :create
end
