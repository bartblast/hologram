# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Readers.Module26 do
  use Hologram.Entity

  attribute :open, :boolean, default: false

  allow :read, when: open == true
end
