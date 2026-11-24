# credo:disable-for-this-file Credo.Check.Readability.Specs
# An entity only a function no code calls names, whose implementation calls Protocol4.
defmodule Hologram.Test.Fixtures.Compiler.ImplReach.Entity9 do
  use Hologram.Entity

  attribute :label, :string

  allow :read
end

defimpl Hologram.Test.Fixtures.Compiler.ImplReach.Protocol,
  for: Hologram.Test.Fixtures.Compiler.ImplReach.Entity9 do
  alias Hologram.Test.Fixtures.Compiler.ImplReach.Protocol4

  def run(entity), do: Protocol4.run(entity.label)
end
