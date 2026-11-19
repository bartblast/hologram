# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Readers.Module29 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Readers.Module25

  attribute :open, :boolean, default: false

  relationship :vault, Module25, optional: true

  allow :read, when: open == true
  allow :read, via: {:archive, vault}
  allow :read, via: {:close, vault}
end
