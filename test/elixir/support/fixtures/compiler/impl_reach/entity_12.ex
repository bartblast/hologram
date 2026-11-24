# credo:disable-for-this-file Credo.Check.Readability.Specs
# An entity no rule lets anyone read, whose implementation names Entity4.
defmodule Hologram.Test.Fixtures.Compiler.ImplReach.Entity12 do
  use Hologram.Entity

  attribute :label, :string
end

defimpl Hologram.Test.Fixtures.Compiler.ImplReach.Protocol,
  for: Hologram.Test.Fixtures.Compiler.ImplReach.Entity12 do
  alias Hologram.Test.Fixtures.Compiler.ImplReach.Entity4

  def run(_entity), do: %Entity4{}
end
