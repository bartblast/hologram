# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module48 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module49

  attribute :label, :string

  relationship :owner, Module49, optional: true
end
