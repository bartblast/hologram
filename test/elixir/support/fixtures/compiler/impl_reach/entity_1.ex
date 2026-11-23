# credo:disable-for-this-file Credo.Check.Readability.Specs
# An entity only server code names, whose implementation spells it and reads nothing.
defmodule Hologram.Test.Fixtures.Compiler.ImplReach.Entity1 do
  use Hologram.Entity

  attribute :label, :string

  allow :read
end

defimpl Hologram.Test.Fixtures.Compiler.ImplReach.Protocol,
  for: Hologram.Test.Fixtures.Compiler.ImplReach.Entity1 do
  alias Hologram.Test.Fixtures.Compiler.ImplReach.Entity1

  def run(%Entity1{} = entity), do: entity.label
end
