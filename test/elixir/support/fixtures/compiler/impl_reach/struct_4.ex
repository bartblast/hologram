# credo:disable-for-this-file Credo.Check.Readability.Specs
# A struct whose implementation of a protocol the runtime dispatches names an entity.
defmodule Hologram.Test.Fixtures.Compiler.ImplReach.Struct4 do
  defstruct []
end

defimpl String.Chars, for: Hologram.Test.Fixtures.Compiler.ImplReach.Struct4 do
  alias Hologram.Test.Fixtures.Compiler.ImplReach.Entity4

  def to_string(_struct), do: Atom.to_string(Entity4)
end
