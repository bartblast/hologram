# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Readers.Module33 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Readers.Module32

  attribute :loose, :boolean, default: false

  relationship :tool, Module32, optional: true

  allow :read
end
