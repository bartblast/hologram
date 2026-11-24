# credo:disable-for-this-file Credo.Check.Readability.Specs
# A plain struct whose implementation is the only code on its page calling Protocol4.
defmodule Hologram.Test.Fixtures.Compiler.ImplReach.Struct5 do
  defstruct [:value]
end

defimpl Hologram.Test.Fixtures.Compiler.ImplReach.Protocol,
  for: Hologram.Test.Fixtures.Compiler.ImplReach.Struct5 do
  alias Hologram.Test.Fixtures.Compiler.ImplReach.Protocol4

  def run(struct), do: Protocol4.run(struct.value)
end
