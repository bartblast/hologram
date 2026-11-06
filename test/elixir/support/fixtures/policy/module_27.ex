# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module27 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module26
  alias Hologram.Test.Fixtures.Policy.Module28
  alias Hologram.Test.Fixtures.Policy.Module29

  attribute :flagged, :boolean, default: false

  relationship :marks, [Module29]
  relationship :space, Module26, optional: true
  relationship :ticket, Module28, optional: true

  # Module28's :close reads it through an any, which a browser answers from rows it holds.
  allow :read
end
