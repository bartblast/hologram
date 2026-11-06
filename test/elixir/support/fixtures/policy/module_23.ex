# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module23 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module22
  alias Hologram.Test.Fixtures.Policy.Module24

  attribute :flagged, :boolean, default: false
  attribute :rank, :integer, optional: true

  relationship :board, Module22, optional: true
  relationship :shelf, Module24, optional: true

  allow :read
end
