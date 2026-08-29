# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module21 do
  use Hologram.Entity

  # A required integer is the one shape a delta may name, and this one is server-only - so the
  # name is withheld before its shape is ever considered.
  attribute :balance, :integer, server_only: true
  attribute :label, :string

  allow :read
  allow :update
end
