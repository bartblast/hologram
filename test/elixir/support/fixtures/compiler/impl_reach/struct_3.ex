# credo:disable-for-this-file Credo.Check.Readability.Specs
# A struct whose implementation dispatches another protocol on an atom.
defmodule Hologram.Test.Fixtures.Compiler.ImplReach.Struct3 do
  defstruct []
end

defimpl Hologram.Test.Fixtures.Compiler.ImplReach.Protocol,
  for: Hologram.Test.Fixtures.Compiler.ImplReach.Struct3 do
  alias Hologram.Test.Fixtures.Compiler.ImplReach.Helper
  alias Hologram.Test.Fixtures.Compiler.ImplReach.Protocol2

  def run(_struct), do: Protocol2.run(Helper.value())
end
