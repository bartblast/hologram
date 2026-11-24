# credo:disable-for-this-file Credo.Check.Readability.Specs
# An entity with a date field, and a time field only the server reads.
defmodule Hologram.Test.Fixtures.Compiler.ImplReach.Entity13 do
  use Hologram.Entity

  attribute :label, :string
  attribute :day, :date
  attribute :opens_at, :time, server_only: true

  allow :read
end
