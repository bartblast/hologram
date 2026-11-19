# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Readers.Module28 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Readers.Module25
  alias Hologram.Test.Fixtures.Policy.Readers.Module26
  alias Hologram.Test.Fixtures.Policy.Readers.Module27

  relationship :crate, Module26, optional: true
  relationship :shelf, Module27, optional: true
  relationship :vault, Module25, optional: true

  allow :read, via: {:update, vault}
  allow :read, via: {:archive, vault}
  allow :read, via: {:delete, vault}
  allow :read, via: {:close, vault}
  allow :read, via: {:read, shelf.crate}
  allow :read, via: {:read, crate}
end
