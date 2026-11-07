# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module34 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module33

  attribute :name, :string, optional: true

  relationship :vault, Module33, optional: true

  allow :read
end
