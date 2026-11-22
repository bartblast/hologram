# credo:disable-for-this-file Credo.Check.Readability.Specs
# An entity nothing names but its implementation of a protocol, which no page dispatches on it.
defmodule Hologram.Test.Fixtures.Compiler.ImplReach.Entity5 do
  use Hologram.Entity

  attribute :label, :string

  allow :read
end

defimpl Hologram.Test.Fixtures.Compiler.ImplReach.Protocol2,
  for: Hologram.Test.Fixtures.Compiler.ImplReach.Entity5 do
  def run(entity), do: entity.label
end
