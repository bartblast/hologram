# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module29 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module28

  attribute :name, :string

  relationship :messages, [Module28], inverse: labels

  allow :read
end
