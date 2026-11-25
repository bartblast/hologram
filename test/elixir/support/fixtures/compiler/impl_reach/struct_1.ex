# credo:disable-for-this-file Credo.Check.Readability.Specs
# A struct whose implementation queries a type nothing else on its page names, through a
# relationship name nothing else there spells.
defmodule Hologram.Test.Fixtures.Compiler.ImplReach.Struct1 do
  defstruct []
end

defimpl Hologram.Test.Fixtures.Compiler.ImplReach.Protocol,
  for: Hologram.Test.Fixtures.Compiler.ImplReach.Struct1 do
  use Hologram.DB

  alias Hologram.Test.Fixtures.Compiler.ImplReach.Entity3

  def run(_struct), do: include(Entity3, owner)
end
