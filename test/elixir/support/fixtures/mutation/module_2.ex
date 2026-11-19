# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Mutation.Module2 do
  use Hologram.Entity

  attribute :public, :boolean, default: false

  allow :read
  allow :create, when: public == true
  allow :delete
end
